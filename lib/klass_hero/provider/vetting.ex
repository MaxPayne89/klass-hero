defmodule KlassHero.Provider.Vetting do
  @moduledoc """
  Vetting track policy: the ordered, composable set of `StepDefinition`s a Provider
  must complete, selected by `entity_type`. Pure domain policy — no persistence,
  no side effects.

  Track composition (which steps, in what order, with which prerequisites) lives
  here, in code, so changes are version-controlled and reviewed. The `:individual`
  track is the 6-step spine; the `:business` track is a follow-up and currently
  carries only its document steps.

  See `docs/6-step-verification-process.md` for the target catalog and
  `docs/adr/0008-provider-vetting-is-a-composable-step-engine.md` for the engine decision.

  Command and query functions that persist and read Vetting Cases are added to this
  module in later parts of the engine slice; `track/1` is the pure policy they build on.
  """

  import Ecto.Query

  alias KlassHero.Provider.Adapters.Driving.Events.EventHandlers.VettingVerificationSync
  alias KlassHero.Provider.CommunityGuidelines
  alias KlassHero.Provider.IdentityVerification
  alias KlassHero.Provider.ProviderProfile
  alias KlassHero.Provider.SignedAgreement
  alias KlassHero.Provider.StaffAttestationPolicy
  alias KlassHero.Provider.StepDefinition
  alias KlassHero.Provider.StripeIdentity
  alias KlassHero.Provider.Verification
  alias KlassHero.Provider.VerificationDocument
  alias KlassHero.Provider.VerificationStep
  alias KlassHero.Provider.VettingCase
  alias KlassHero.Provider.VettingChecklist
  alias KlassHero.Provider.VettingStepView
  alias KlassHero.Repo
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.EventDispatchHelper

  require Logger

  @individual_track [
    %StepDefinition{key: :identity, completed_via: {:stripe_identity}, admin_review: false},
    %StepDefinition{key: :experience, completed_via: {:document, "experience_validation"}, admin_review: true},
    %StepDefinition{key: :background, completed_via: {:document, "background_check"}, admin_review: true},
    %StepDefinition{key: :video, completed_via: {:document, "video_screening"}, admin_review: true, dedicated: :widget},
    %StepDefinition{key: :safeguarding, completed_via: {:document, "safeguarding_certificate"}, admin_review: true},
    %StepDefinition{
      key: :community_agreement,
      completed_via: {:signed_agreement, :community_agreement},
      admin_review: false
    }
  ]

  @business_track [
    %StepDefinition{
      key: :responsible_person_identity,
      completed_via: {:stripe_identity},
      admin_review: false,
      dedicated: :widget
    },
    %StepDefinition{
      key: :business_registration,
      completed_via: {:document, "business_registration"},
      admin_review: true,
      dedicated: :command
    },
    %StepDefinition{
      key: :insurance,
      completed_via: {:document, "insurance_certificate"},
      admin_review: true,
      dedicated: :widget
    },
    %StepDefinition{
      key: :community_agreement,
      completed_via: {:signed_agreement, :community_agreement},
      requires: [:responsible_person_identity],
      admin_review: false
    },
    %StepDefinition{
      key: :staff_attestation,
      completed_via: {:signed_agreement, :staff_attestation},
      requires: [:responsible_person_identity],
      admin_review: false
    }
  ]

  @doc """
  Returns the ordered list of `StepDefinition`s for the given `entity_type`.
  """
  @spec track(:individual | :business) :: [StepDefinition.t()]
  def track(:individual), do: @individual_track
  def track(:business), do: @business_track

  # ── Persistence (imperative shell) ─────────────────────────────────────────

  @doc """
  Returns the provider's vetting case with its steps preloaded in track order.

  Lazily backfills a case for providers created before the engine existed: on first
  read, builds the case for the provider's `entity_type` track. Race-safe via the
  `provider_id` unique index — a losing concurrent insert re-reads the winner.
  Returns `{:error, :not_found}` only when the *provider* itself is absent.
  """
  @spec get_case_for_provider(String.t()) :: {:ok, VettingCase.t()} | {:error, :not_found}
  def get_case_for_provider(provider_id) do
    case load_case_by_provider(provider_id) do
      nil -> backfill_case(provider_id)
      case_ -> {:ok, case_}
    end
  end

  @doc """
  Seeds a vetting case for a provider on the track selected by `entity_type`.
  Returns `{:ok, case}` (steps preloaded) or an insert error changeset.
  """
  @spec create_case(String.t(), :individual | :business) ::
          {:ok, VettingCase.t()} | {:error, Ecto.Changeset.t()}
  def create_case(provider_id, entity_type) do
    provider_id
    |> VettingCase.new_for_track(entity_type)
    |> VettingCase.create_changeset()
    |> Repo.insert()
    |> case do
      {:ok, case_} -> {:ok, Repo.preload(case_, steps: step_order())}
      error -> error
    end
  end

  @doc """
  Persists the aggregate's current steps and lifecycle back to an already-persisted
  case, in one transaction. Each row is written unconditionally with `Repo.update_all`
  keyed by id: the mutable attrs are already in hand, so no read-before-write is needed
  and `updated_at` is bumped explicitly (update_all does not touch timestamps). Returns
  the passed-in case unchanged — callers already hold the post-mutation aggregate with
  its steps loaded, so a re-fetch would be pure waste.
  """
  @spec save_case(VettingCase.t()) :: {:ok, VettingCase.t()} | {:error, term()}
  def save_case(%VettingCase{} = case_) do
    Repo.transaction(fn -> write_case!(case_, DateTime.utc_now()) end)
  end

  # The non-transactional core of save_case: unconditional row writes, no BEGIN/COMMIT of its
  # own. Callers that already hold a transaction (e.g. the responsible-person change) compose
  # this directly instead of nesting a second `Repo.transaction`.
  defp write_case!(%VettingCase{id: id, steps: steps, lifecycle: lifecycle} = case_, now) do
    Repo.update_all(from(c in VettingCase, where: c.id == ^id),
      set: [lifecycle: lifecycle, updated_at: now]
    )

    Enum.each(steps, &save_step!(&1, now))
    case_
  end

  defp save_step!(%VerificationStep{id: step_id} = step, now) do
    set = step |> step_mutable_attrs() |> Map.to_list() |> Keyword.put(:updated_at, now)
    Repo.update_all(from(s in VerificationStep, where: s.id == ^step_id), set: set)
  end

  defp step_mutable_attrs(%VerificationStep{} = step) do
    Map.take(step, [:status, :evidence_ref, :rejection_reason, :reviewed_by_id, :reviewed_at, :submitted_at])
  end

  defp load_case_by_provider(provider_id) do
    VettingCase
    |> where([c], c.provider_id == ^provider_id)
    |> preload(steps: ^step_order())
    |> Repo.one()
  end

  defp backfill_case(provider_id) do
    case provider_entity_type(provider_id) do
      {:error, :not_found} -> {:error, :not_found}
      {:ok, entity_type} -> insert_or_reload(provider_id, entity_type)
    end
  end

  defp insert_or_reload(provider_id, entity_type) do
    case create_case(provider_id, entity_type) do
      {:ok, case_} -> {:ok, case_}
      # A concurrent insert won the unique index; re-read the winner.
      {:error, %Ecto.Changeset{}} -> {:ok, load_case_by_provider(provider_id)}
    end
  end

  defp provider_entity_type(provider_id) do
    case Repo.one(from(p in ProviderProfile, where: p.id == ^provider_id, select: p.entity_type)) do
      nil -> {:error, :not_found}
      entity_type -> {:ok, entity_type}
    end
  end

  defp step_order, do: from(s in VerificationStep, order_by: s.inserted_at)

  # ── Responsible Person (Slice B1) ──────────────────────────────────────────

  @doc """
  Sets a business provider's Responsible Person (ADR-0010) — the sole mutator of
  `responsible_person_name`/`responsible_person_role` and the only business vetting
  reset trigger. Compares the submitted `(name, role)` to the stored values by
  normalized exact match:

  - `:unchanged` — a no-op (the typo-guard): no write, no reset.
  - `:set` — first capture: persist only.
  - `:changed` — persist the new person, reset the `:responsible_person_identity`
    step (cascading to the community-agreement and staff-attestation steps via the
    `requires` graph), and unverify the provider if it was verified.

  The person-write and the case reset land in one transaction; the unverify publishes
  `provider_unverified`, so it runs after the commit (never inside the transaction).
  """
  @spec set_responsible_person(String.t(), String.t() | nil, String.t() | nil) ::
          {:ok, :unchanged | :set | :changed} | {:error, term()}
  def set_responsible_person(provider_id, name, role) when is_binary(provider_id) do
    with {:ok, profile} <- fetch_profile(provider_id) do
      apply_responsible_person_change(profile, name, role)
    end
  end

  # The shared "load the profile or 404" open of every Vetting command that mutates
  # a provider row (set_responsible_person, submit_business_registration).
  defp fetch_profile(provider_id) do
    case Repo.get(ProviderProfile, provider_id) do
      nil -> {:error, :not_found}
      profile -> {:ok, profile}
    end
  end

  defp apply_responsible_person_change(profile, name, role) do
    case ProviderProfile.responsible_person_change(profile, name, role) do
      :unchanged -> {:ok, :unchanged}
      :set -> with {:ok, _} <- persist_responsible_person(profile, name, role), do: {:ok, :set}
      :changed -> change_responsible_person(profile, name, role)
    end
  end

  defp persist_responsible_person(profile, name, role) do
    profile
    |> ProviderProfile.responsible_person_changeset(%{
      responsible_person_name: name,
      responsible_person_role: role
    })
    |> Repo.update()
  end

  defp change_responsible_person(profile, name, role) do
    # Load and reset the case OUTSIDE the transaction. `get_case_for_provider` may lazily
    # backfill via a bare insert guarded by the `provider_id` unique index; nesting that
    # inside the transaction would let a lost concurrent-insert race poison the whole
    # transaction (the #1065 class of bug). Only the two pure writes go in the txn.
    with {:ok, case_} <- get_case_for_provider(profile.id),
         {:ok, key} <- fetch_identity_step_key(case_),
         {:ok, reset} <- VettingCase.reset_step(case_, key),
         {:ok, :ok} <- persist_change_in_transaction(profile, name, role, reset) do
      VettingVerificationSync.maybe_unverify(profile.id, nil)
      VettingVerificationSync.broadcast_updated(profile.id)
      {:ok, :changed}
    end
  end

  defp persist_change_in_transaction(profile, name, role, reset_case) do
    Repo.transaction(fn ->
      case persist_responsible_person(profile, name, role) do
        {:ok, _} ->
          write_case!(reset_case, DateTime.utc_now())
          :ok

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Sets the Responsible Person, then starts their Stripe Identity verification — the one
  UI surface for the business identity step (ADR-0010). Wrapping set-then-start means the
  LiveView never holds the torn state where the person is saved but no session is in flight.

  Returns the hosted `redirect_url` plus the `change` outcome from the set, so the caller
  can surface "Identity reset — please re-verify" only when `change == :changed`.
  """
  @spec start_responsible_person_verification(String.t(), String.t() | nil, String.t() | nil, String.t()) ::
          {:ok, %{redirect_url: String.t(), change: :unchanged | :set | :changed}} | {:error, term()}
  def start_responsible_person_verification(provider_id, name, role, return_url)
      when is_binary(provider_id) and is_binary(return_url) do
    with {:ok, change} <- set_responsible_person(provider_id, name, role),
         {:ok, %{redirect_url: url}} <- create_identity_verification_session(provider_id, return_url) do
      {:ok, %{redirect_url: url, change: change}}
    end
  end

  # ── Business Registration (Slice B2) ───────────────────────────────────────

  @doc """
  Captures a business provider's registration facts (legal name, number, country — ADR-0011)
  and inserts the registration document in one transaction (issue #956). The storage upload
  runs first, outside the transaction (storage is not transactional); the field changeset is
  validated before the upload so invalid input never orphans a file.

  Unlike the Responsible Person, registration is a fact about the entity: it carries no
  `requires` edge and never resets vetting (ADR-0010). The `:business_registration` step
  advances only when an admin later approves the document (the generic
  `AdvanceVettingStepOnDocumentReview` path); submission alone just makes the pending document
  exist, which the checklist read merge surfaces as "Under review".
  """
  @spec submit_business_registration(String.t(), map()) ::
          {:ok, VerificationDocument.t()} | {:error, Ecto.Changeset.t() | term()}
  def submit_business_registration(provider_id, attrs) when is_binary(provider_id) and is_map(attrs) do
    with {:ok, profile} <- fetch_profile(provider_id) do
      persist_business_registration(profile, attrs)
    end
  end

  defp persist_business_registration(profile, attrs) do
    fields = Map.take(attrs, [:legal_business_name, :registration_number, :registration_country])
    changeset = ProviderProfile.business_registration_changeset(profile, fields)

    with {:ok, _} <- Ecto.Changeset.apply_action(changeset, :update),
         {:ok, file_url} <- Verification.upload_document_file(Map.put(attrs, :provider_profile_id, profile.id)) do
      persist_registration_in_transaction(changeset, profile.id, attrs, file_url)
    end
  end

  defp persist_registration_in_transaction(changeset, provider_id, attrs, file_url) do
    doc_params = Map.merge(attrs, %{provider_profile_id: provider_id, document_type: "business_registration"})

    Repo.transaction(fn ->
      with {:ok, _profile} <- Repo.update(changeset),
           {:ok, doc} <- Verification.insert_verification_document(doc_params, file_url) do
        doc
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # ── Onboarding checklist read model (Slice 2) ──────────────────────────────

  @doc """
  Assembles a provider's onboarding checklist: the vetting case lifecycle plus an ordered
  per-step view whose status re-surfaces `:rejected` from the latest evidence record.

  The engine resets document/identity steps to `:not_started` on rejection (clearing the
  step's own reason — see `VettingCase.reset_step/2`), so a step's *displayed* status and
  reason are a merge of the engine step and its evidence (`VerificationDocument`,
  `IdentityVerification`). This is the single read entry point, so the LiveView never
  orchestrates several reads. The case is lazily created on first read — never `:not_found`.
  """
  @spec checklist_for_provider(String.t()) :: VettingChecklist.t()
  def checklist_for_provider(provider_id) when is_binary(provider_id) do
    {:ok, case_} = get_case_for_provider(provider_id)
    {:ok, documents} = Verification.get_provider_verification_documents(provider_id)
    identity = latest_identity(provider_id)

    evidence = %{documents: documents, identity: identity}
    step_views = Enum.map(case_.steps, &derive_step_view(&1, evidence, case_.entity_type))

    build_checklist(case_, step_views)
  end

  @doc """
  Returns the provider's latest Stripe Identity verification record, or `{:error, :not_found}`.
  Newest by insertion — retries append new records.
  """
  @spec get_latest_identity_verification(String.t()) ::
          {:ok, IdentityVerification.t()} | {:error, :not_found}
  def get_latest_identity_verification(provider_id) when is_binary(provider_id) do
    IdentityVerification
    |> where([i], i.provider_id == ^provider_id)
    |> order_by([i], desc: i.inserted_at)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      iv -> {:ok, iv}
    end
  end

  @doc """
  Lists all identity verifications with their provider's business name for admin review,
  newest first. Read-only — admins never override a Stripe Identity outcome (ADR 0009).
  """
  @spec list_identity_verifications_for_admin() ::
          {:ok, [%{identity_verification: IdentityVerification.t(), provider_business_name: String.t()}]}
  def list_identity_verifications_for_admin do
    results =
      from(i in IdentityVerification,
        join: p in ProviderProfile,
        on: p.id == i.provider_id,
        order_by: [desc: i.inserted_at],
        select: %{identity_verification: i, provider_business_name: p.business_name}
      )
      |> Repo.all()

    {:ok, results}
  end

  @doc "Whether the provider's identity step is engine-approved (drives the overview CTA banner)."
  @spec identity_step_approved?(String.t()) :: boolean()
  def identity_step_approved?(provider_id) when is_binary(provider_id) do
    case get_case_for_provider(provider_id) do
      {:ok, case_} -> Enum.any?(case_.steps, &(&1.key == :identity and VerificationStep.approved?(&1)))
      {:error, :not_found} -> false
    end
  end

  # Builds a step's *displayed* status + reason by merging the engine step with its evidence.
  # `step.status` is authoritative for `:approved`; for everything else the evidence record
  # wins, because the engine resets document/identity steps to `:not_started` on rejection and
  # discards the reason. Each `step_status/2` clause covers every shape its evidence can take,
  # including absent evidence (`nil`), which falls back to the step.
  defp derive_step_view(%VerificationStep{} = step, evidence, entity_type) do
    {ui_status, reason} = step_status(step, evidence)

    %VettingStepView{
      key: step.key,
      ui_status: ui_status,
      rejection_reason: reason,
      admin_review: step.admin_review,
      completed_via: step.completed_via,
      dedicated: dedicated_for_step_key(entity_type, step.key)
    }
  end

  # A step's `dedicated` marker, read from the current track catalog by key — static policy, so it
  # is resolved at display time rather than frozen into the step (no migration). Drives the
  # presenter's single dedicated-widget clause; defaults to false for a key absent from the track.
  defp dedicated_for_step_key(entity_type, key) do
    case Enum.find(track(entity_type), &(&1.key == key)) do
      %StepDefinition{dedicated: dedicated} -> dedicated
      nil -> false
    end
  end

  defp step_status(%VerificationStep{status: :approved}, _evidence), do: {:approved, nil}

  defp step_status(%VerificationStep{completed_via: {:document, type}} = step, %{documents: documents}) do
    # `get_provider_verification_documents/1` returns documents newest-first, so the first
    # match is the latest of its type.
    documents
    |> Enum.find(&(&1.document_type == String.to_existing_atom(type)))
    |> document_status(step)
  end

  defp step_status(%VerificationStep{completed_via: {:stripe_identity}} = step, %{identity: identity}) do
    identity_status(identity, step)
  end

  # Agreements auto-approve with no reject path, so the engine step is the whole story.
  defp step_status(%VerificationStep{completed_via: {:signed_agreement, _kind}} = step, _evidence) do
    {step.status, nil}
  end

  defp document_status(%VerificationDocument{status: :rejected, rejection_reason: reason}, _step) do
    {:rejected, reason}
  end

  defp document_status(%VerificationDocument{status: :pending}, _step), do: {:submitted, nil}
  defp document_status(_doc_or_nil, step), do: {step.status, nil}

  defp identity_status(%IdentityVerification{outcome: :fail, failure_reason: reason}, _step) do
    {:rejected, reason}
  end

  defp identity_status(%IdentityVerification{status: :processing}, _step), do: {:submitted, nil}
  defp identity_status(_identity_or_nil, step), do: {step.status, nil}

  defp build_checklist(%VettingCase{} = case_, step_views) do
    approved = Enum.count(step_views, &(&1.ui_status == :approved))

    %VettingChecklist{
      lifecycle: case_.lifecycle,
      entity_type: case_.entity_type,
      verified?: VettingCase.verified?(case_),
      approved_count: approved,
      total_count: length(step_views),
      steps: step_views
    }
  end

  defp latest_identity(provider_id) do
    case get_latest_identity_verification(provider_id) do
      {:ok, identity} -> identity
      {:error, :not_found} -> nil
    end
  end

  # ── Signed agreements (community agreement B4 / staff attestation B5) ───────
  #
  # Both business-track signed-agreement steps share one query/policy shape, differing only by
  # `kind` and the policy module that owns the version. The public per-kind functions are readable
  # names over the shared internals; the `kind -> policy` dispatch lives here (the engine hub), so
  # the submit command stays ignorant of which concrete policy modules exist.

  @doc "Returns the provider's most recent Community Standards Agreement, or `nil` if never signed."
  @spec get_latest_community_agreement(String.t()) :: SignedAgreement.t() | nil
  def get_latest_community_agreement(provider_id), do: get_latest_signed_agreement(provider_id, :community_agreement)

  @doc "Returns the provider's most recent staff attestation, or `nil` if never signed."
  @spec get_latest_staff_attestation(String.t()) :: SignedAgreement.t() | nil
  def get_latest_staff_attestation(provider_id), do: get_latest_signed_agreement(provider_id, :staff_attestation)

  @doc "Returns the provider's most recent signed agreement of `kind`, or `nil` if never signed."
  @spec get_latest_signed_agreement(String.t(), SignedAgreement.kind()) :: SignedAgreement.t() | nil
  def get_latest_signed_agreement(provider_id, kind) when is_binary(provider_id) do
    SignedAgreement
    |> where([a], a.provider_id == ^provider_id and a.kind == ^kind)
    |> order_by([a], desc: a.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Returns `true` when the provider's latest Community Standards Agreement still satisfies the
  current guidelines (no re-agreement required); `false` when never signed or out of date.

  Accepts a `provider_id` (fetches the latest agreement) or an already-fetched
  `SignedAgreement`/`nil` (no query) — the caller already holding the record avoids a re-read.
  """
  @spec community_agreement_satisfied?(String.t() | SignedAgreement.t() | nil) :: boolean()
  def community_agreement_satisfied?(provider_id) when is_binary(provider_id),
    do: provider_id |> get_latest_community_agreement() |> CommunityGuidelines.agreement_satisfied?()

  def community_agreement_satisfied?(agreement), do: CommunityGuidelines.agreement_satisfied?(agreement)

  @doc "As `community_agreement_satisfied?/1`, for the staff Compliance Declaration (B5)."
  @spec staff_attestation_satisfied?(String.t() | SignedAgreement.t() | nil) :: boolean()
  def staff_attestation_satisfied?(provider_id) when is_binary(provider_id),
    do: provider_id |> get_latest_staff_attestation() |> StaffAttestationPolicy.attestation_satisfied?()

  def staff_attestation_satisfied?(agreement), do: StaffAttestationPolicy.attestation_satisfied?(agreement)

  @doc "Returns `true` when the given entity type's track includes the community-agreement step."
  @spec requires_community_agreement?(:individual | :business) :: boolean()
  def requires_community_agreement?(entity_type), do: requires_signed_agreement?(entity_type, :community_agreement)

  @doc "Returns `true` when the given entity type's track includes the staff-attestation step."
  @spec requires_staff_attestation?(:individual | :business) :: boolean()
  def requires_staff_attestation?(entity_type), do: requires_signed_agreement?(entity_type, :staff_attestation)

  @spec requires_signed_agreement?(:individual | :business, SignedAgreement.kind()) :: boolean()
  def requires_signed_agreement?(entity_type, kind) do
    entity_type
    |> track()
    |> Enum.any?(&match?(%StepDefinition{completed_via: {:signed_agreement, ^kind}}, &1))
  end

  @doc "The Community Guidelines version currently in force."
  @spec current_community_guidelines_version() :: String.t()
  def current_community_guidelines_version, do: current_signed_agreement_version(:community_agreement)

  @doc "The published version of the signed-agreement policy for `kind` (used at sign time)."
  @spec current_signed_agreement_version(SignedAgreement.kind()) :: String.t()
  def current_signed_agreement_version(:community_agreement), do: CommunityGuidelines.current_version()
  def current_signed_agreement_version(:staff_attestation), do: StaffAttestationPolicy.current_version()

  # ── Stripe Identity (Slice 1) ──────────────────────────────────────────────

  @doc """
  Starts a Stripe Identity verification for a provider: creates a hosted session, records
  an `IdentityVerification` (`:processing`) keyed by the session id, and submits the
  provider's `:identity` step so the case reflects work in progress. Returns the hosted
  `redirect_url`; the pass/fail outcome arrives later by webhook (ADR-0009).
  """
  @spec create_identity_verification_session(String.t(), String.t()) ::
          {:ok, %{redirect_url: String.t()}} | {:error, term()}
  def create_identity_verification_session(provider_id, return_url)
      when is_binary(provider_id) and is_binary(return_url) do
    # Fetch the case (and gate a business on its captured responsible person) BEFORE minting the
    # Stripe session, so a rejected bypass never leaves an orphan session or IdentityVerification row.
    with {:ok, case_} <- get_case_for_provider(provider_id),
         :ok <- ensure_business_responsible_person(provider_id, case_),
         {:ok, %{session_id: session_id, url: url}} <-
           StripeIdentity.create_session(%{provider_id: provider_id, return_url: return_url}),
         {:ok, _iv} <-
           create_identity_verification(
             IdentityVerification.new(%{provider_id: provider_id, stripe_session_id: session_id})
           ),
         {:ok, key} <- fetch_identity_step_key(case_),
         {:ok, updated} <- VettingCase.submit_step(case_, key),
         {:ok, _} <- save_case(updated) do
      {:ok, %{redirect_url: url}}
    end
  end

  # ADR-0010: a business's identity step verifies its Responsible Person, whose name must be
  # captured (via set_responsible_person) first. The one legit surface,
  # start_responsible_person_verification/4, sets the person before calling this; a direct
  # "start_identity_verification" event on a business bypasses that — this gate fails it closed.
  # Individuals verify themselves, so no responsible person is required.
  defp ensure_business_responsible_person(_provider_id, %VettingCase{entity_type: :individual}), do: :ok

  defp ensure_business_responsible_person(provider_id, %VettingCase{entity_type: :business}) do
    with {:ok, profile} <- fetch_profile(provider_id) do
      if ProviderProfile.responsible_person_captured?(profile),
        do: :ok,
        else: {:error, :responsible_person_required}
    end
  end

  @doc """
  Records the outcome of a Stripe Identity session (delivered by webhook) against its
  `IdentityVerification`, applying the fail-closed age gate, and emits the domain event that
  advances the `:identity` step. Idempotent: an unknown session id is `{:ok, :ignored}`, a
  record already terminal is `{:ok, :already_recorded}`.

  Input (normalised by the webhook controller):
  `%{session_id, stripe_status: :verified | :requires_input | :canceled, dob, today}`.
  """
  @spec record_identity_verification_outcome(map()) ::
          {:ok, IdentityVerification.t() | :ignored | :already_recorded} | {:error, term()}
  def record_identity_verification_outcome(%{session_id: session_id} = outcome) do
    case get_identity_verification_by_session(session_id) do
      {:error, :not_found} -> {:ok, :ignored}
      {:ok, %IdentityVerification{status: :processing} = iv} -> apply_identity_outcome(iv, outcome)
      {:ok, %IdentityVerification{}} -> {:ok, :already_recorded}
    end
  end

  defp fetch_identity_step_key(case_) do
    case VettingCase.step_key_for_identity(case_) do
      nil -> {:error, :no_identity_step}
      key -> {:ok, key}
    end
  end

  defp apply_identity_outcome(iv, outcome) do
    case resolve_identity_outcome(iv, outcome) do
      :ignore ->
        {:ok, :ignored}

      {updated, event_type} ->
        with {:ok, persisted} <- update_identity_verification(updated) do
          dispatch_identity_event(event_type, persisted)
          {:ok, persisted}
        end
    end
  end

  # A Stripe `:verified` status is NOT automatically a pass — the age gate can still fail
  # it, so we read the resulting record's `outcome`. An unmapped status fails closed:
  # log and no-op (`:ignore`), never fabricating a pass/fail.
  defp resolve_identity_outcome(%IdentityVerification{} = iv, %{stripe_status: :verified, dob: dob, today: today}) do
    updated = IdentityVerification.mark_verified(iv, dob, today)
    {updated, identity_event_for(updated.outcome)}
  end

  defp resolve_identity_outcome(%IdentityVerification{} = iv, %{stripe_status: :requires_input}) do
    {IdentityVerification.mark_requires_input(iv), :identity_verification_failed}
  end

  defp resolve_identity_outcome(%IdentityVerification{} = iv, %{stripe_status: :canceled}) do
    {IdentityVerification.mark_canceled(iv), :identity_verification_failed}
  end

  defp resolve_identity_outcome(%IdentityVerification{}, %{stripe_status: stripe_status}) do
    Logger.warning("Ignoring unmapped Stripe identity status: #{inspect(stripe_status)}")
    :ignore
  end

  defp identity_event_for(:pass), do: :identity_verification_passed
  defp identity_event_for(:fail), do: :identity_verification_failed

  defp dispatch_identity_event(event_type, iv) do
    DomainEvent.new(event_type, iv.id, :identity_verification, %{
      provider_id: iv.provider_id,
      identity_verification_id: iv.id,
      stripe_session_id: iv.stripe_session_id,
      failure_reason: iv.failure_reason
    })
    |> EventDispatchHelper.dispatch(KlassHero.Provider)
  end

  defp create_identity_verification(%IdentityVerification{} = iv) do
    attrs = Map.take(iv, ~w(id provider_id stripe_session_id status outcome failure_reason verified_at)a)

    %IdentityVerification{}
    |> IdentityVerification.create_changeset(attrs)
    |> Repo.insert()
  end

  defp get_identity_verification_by_session(session_id) do
    case Repo.one(from(i in IdentityVerification, where: i.stripe_session_id == ^session_id)) do
      nil -> {:error, :not_found}
      iv -> {:ok, iv}
    end
  end

  defp update_identity_verification(%IdentityVerification{id: id} = iv) do
    IdentityVerification
    |> Repo.get!(id)
    |> IdentityVerification.review_changeset(Map.take(iv, ~w(status outcome failure_reason verified_at)a))
    |> Repo.update()
  end
end
