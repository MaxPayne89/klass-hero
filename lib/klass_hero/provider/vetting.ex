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

  alias KlassHero.Provider.ProviderProfile
  alias KlassHero.Provider.StepDefinition
  alias KlassHero.Provider.VerificationStep
  alias KlassHero.Provider.VettingCase
  alias KlassHero.Repo

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
end
