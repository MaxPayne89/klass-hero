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

  alias KlassHero.Provider.IdentityVerification
  alias KlassHero.Provider.ProviderProfile
  alias KlassHero.Provider.StepDefinition
  alias KlassHero.Provider.StripeIdentity
  alias KlassHero.Provider.VerificationStep
  alias KlassHero.Provider.VettingCase
  alias KlassHero.Repo
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.EventDispatchHelper

  require Logger

  @individual_track [
    %StepDefinition{key: :identity, completed_via: {:stripe_identity}, admin_review: false},
    %StepDefinition{key: :experience, completed_via: {:document, "experience_validation"}, admin_review: true},
    %StepDefinition{key: :background, completed_via: {:document, "background_check"}, admin_review: true},
    %StepDefinition{key: :video, completed_via: {:document, "video_screening"}, admin_review: true},
    %StepDefinition{key: :safeguarding, completed_via: {:document, "safeguarding_certificate"}, admin_review: true},
    %StepDefinition{
      key: :community_agreement,
      completed_via: {:signed_agreement, :community_agreement},
      admin_review: false
    }
  ]

  @business_track [
    %StepDefinition{
      key: :business_registration,
      completed_via: {:document, "business_registration"},
      admin_review: true
    },
    %StepDefinition{key: :insurance, completed_via: {:document, "insurance_certificate"}, admin_review: true}
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
  case, in one transaction. Each step is updated from its stored row so Ecto sees the
  real field changes (a `put_assoc` of already-persisted structs diffs to nothing).
  """
  @spec save_case(VettingCase.t()) :: {:ok, VettingCase.t()} | {:error, term()}
  def save_case(%VettingCase{id: id, steps: steps, lifecycle: lifecycle}) do
    Repo.transaction(fn ->
      VettingCase
      |> Repo.get!(id)
      |> Ecto.Changeset.change(lifecycle: lifecycle)
      |> Repo.update!()

      Enum.each(steps, &save_step!/1)
      VettingCase |> Repo.get!(id) |> Repo.preload(steps: step_order())
    end)
  end

  defp save_step!(%VerificationStep{id: step_id} = step) do
    VerificationStep
    |> Repo.get!(step_id)
    |> VerificationStep.changeset(step_mutable_attrs(step))
    |> Repo.update!()
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
    with {:ok, %{session_id: session_id, url: url}} <-
           StripeIdentity.create_session(%{provider_id: provider_id, return_url: return_url}),
         {:ok, _iv} <-
           create_identity_verification(
             IdentityVerification.new(%{provider_id: provider_id, stripe_session_id: session_id})
           ),
         {:ok, case_} <- get_case_for_provider(provider_id),
         {:ok, key} <- fetch_identity_step_key(case_),
         {:ok, updated} <- VettingCase.submit_step(case_, key),
         {:ok, _} <- save_case(updated) do
      {:ok, %{redirect_url: url}}
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
