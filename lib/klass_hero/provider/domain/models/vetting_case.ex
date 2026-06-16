defmodule KlassHero.Provider.Domain.Models.VettingCase do
  @moduledoc """
  The aggregate root for a Provider's Vetting — one case per Provider, owning that
  provider's ordered `VerificationStep`s and the vetting lifecycle.

  Lifecycle: `:not_started → :in_progress → :verified`; a reset (see `reset_step/2`) moves it
  `:verified → :in_progress`. Granular `:submitted` / `:rejected` live on the steps. When the
  case reaches `:verified`, the published `ProviderProfile.verified` fact is set by the
  `VerifyProvider` command — the case is the internal source of truth, `verified` the boundary
  projection.

  Pure domain model. The case computes its own invariants from its frozen steps and never
  consults the track policy after creation.
  """

  use KlassHero.Shared.Domain.Models.PersistenceSupport

  alias KlassHero.Provider.Domain.Models.VerificationStep
  alias KlassHero.Provider.Domain.Services.Vetting

  @enforce_keys [:provider_id, :entity_type]
  defstruct [:id, :provider_id, :entity_type, steps: [], lifecycle: :not_started]

  @type lifecycle :: :not_started | :in_progress | :verified

  @type t :: %__MODULE__{
          id: String.t() | nil,
          provider_id: String.t(),
          entity_type: :individual | :business,
          steps: [VerificationStep.t()],
          lifecycle: lifecycle()
        }

  @doc """
  Builds a new case for a Provider, freezing the steps of the track selected by `entity_type`.
  """
  @spec new_for_track(String.t(), :individual | :business) :: t()
  def new_for_track(provider_id, entity_type) do
    id = Ecto.UUID.generate()

    steps =
      entity_type
      |> Vetting.track()
      |> Enum.map(&VerificationStep.from_definition(&1, id))

    %__MODULE__{id: id, provider_id: provider_id, entity_type: entity_type, steps: steps, lifecycle: :not_started}
  end

  @doc "Returns true when the case has steps and all of them are approved."
  @spec verified?(t()) :: boolean()
  def verified?(%__MODULE__{steps: []}), do: false
  def verified?(%__MODULE__{steps: steps}), do: Enum.all?(steps, &VerificationStep.approved?/1)

  @doc """
  Approves the step with the given key (submitting it first if needed), recording the reviewer
  and evidence, then recomputes the lifecycle. Idempotent for an already-approved step.
  """
  @spec approve_step(t(), atom(), String.t(), String.t() | nil) :: {:ok, t()} | {:error, term()}
  def approve_step(%__MODULE__{} = case_, key, reviewer_id, evidence_ref) do
    with {:ok, step} <- fetch_step(case_, key) do
      if VerificationStep.approved?(step) do
        {:ok, case_}
      else
        with {:ok, submitted} <- ensure_submitted(step),
             {:ok, approved} <- VerificationStep.approve(submitted, reviewer_id, evidence_ref) do
          {:ok, case_ |> replace_step(approved) |> recompute()}
        end
      end
    end
  end

  @doc """
  Recomputes the lifecycle from the current step statuses:
  all approved → `:verified`; all not_started → `:not_started`; otherwise `:in_progress`.
  """
  @spec recompute(t()) :: t()
  def recompute(%__MODULE__{} = case_) do
    %{case_ | lifecycle: lifecycle_for(case_)}
  end

  @doc "Finds the step whose `completed_via` consumes the given document type, if any."
  @spec step_key_for_document(t(), String.t()) :: atom() | nil
  def step_key_for_document(%__MODULE__{steps: steps}, document_type) do
    Enum.find_value(steps, fn step ->
      if step.completed_via == {:document, document_type}, do: step.key
    end)
  end

  @doc """
  Resets the step with the given key and every step that transitively depends on it (the
  reverse-edge closure of `requires`) back to `:not_started`, then recomputes the lifecycle.

  Powers two flows: a rejected document resets its own step (no dependents in the individual
  track), and a business responsible-person change resets identity, cascading to the steps
  that require it.
  """
  @spec reset_step(t(), atom()) :: {:ok, t()} | {:error, term()}
  def reset_step(%__MODULE__{} = case_, key) do
    with {:ok, _step} <- fetch_step(case_, key) do
      keys_to_reset = MapSet.put(dependent_keys(case_.steps, key), key)

      steps =
        Enum.map(case_.steps, fn step ->
          if MapSet.member?(keys_to_reset, step.key) do
            {:ok, reset} = VerificationStep.reset(step)
            reset
          else
            step
          end
        end)

      {:ok, recompute(%{case_ | steps: steps})}
    end
  end

  # --- internals ---------------------------------------------------------------

  defp fetch_step(%__MODULE__{steps: steps}, key) do
    case Enum.find(steps, &(&1.key == key)) do
      nil -> {:error, :step_not_found}
      step -> {:ok, step}
    end
  end

  # Returns the set of step keys that transitively require `key` — i.e. every step that must be
  # reset when `key` is reset. `steps` carry their frozen `requires` (a step's direct
  # prerequisites); we need the *reverse* edges: the keys whose `requires` chain reaches `key`.
  #
  # Example: given identity ← agreement ← attestation (attestation requires agreement requires
  # identity), dependent_keys(steps, :identity) must return #MapSet<[:agreement, :attestation]>.
  # The target key itself is added by the caller, so it must NOT be in the returned set.
  # Implemented as a fixpoint: re-scan all steps until a full pass adds nothing new.
  @spec dependent_keys([VerificationStep.t()], atom()) :: MapSet.t(atom())
  defp dependent_keys(steps, key) do
    grow(steps, key, MapSet.new())
  end

  defp grow(steps, key, set) do
    next = run_dependent_keys(steps, set, key)
    if MapSet.equal?(next, set), do: set, else: grow(steps, key, next)
  end

  defp run_dependent_keys(steps, set, key) do
    Enum.reduce(steps, set, fn step, acc ->
      if Enum.any?(step.requires, &(&1 == key || MapSet.member?(acc, &1))) do
        MapSet.put(acc, step.key)
      else
        acc
      end
    end)
  end

  defp ensure_submitted(%VerificationStep{status: :submitted} = step), do: {:ok, step}
  defp ensure_submitted(%VerificationStep{} = step), do: VerificationStep.submit(step)

  defp replace_step(%__MODULE__{steps: steps} = case_, %VerificationStep{key: key} = updated) do
    %{case_ | steps: Enum.map(steps, fn step -> if step.key == key, do: updated, else: step end)}
  end

  defp lifecycle_for(%__MODULE__{steps: []}), do: :not_started

  defp lifecycle_for(%__MODULE__{steps: steps} = case_) do
    cond do
      verified?(case_) -> :verified
      Enum.all?(steps, &(&1.status == :not_started)) -> :not_started
      true -> :in_progress
    end
  end
end
