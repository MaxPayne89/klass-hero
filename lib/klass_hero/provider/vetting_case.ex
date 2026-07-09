defmodule KlassHero.Provider.VettingCase do
  @moduledoc """
  The aggregate root for a Provider's Vetting — one case per Provider, owning that
  provider's ordered `VerificationStep`s and the vetting lifecycle
  (`vetting_cases` table).

  Lifecycle: `:not_started → :in_progress → :verified`; a reset (see `reset_step/2`)
  moves it `:verified → :in_progress`. Granular `:submitted` / `:rejected` live on the
  steps. When the case reaches `:verified`, the published `ProviderProfile.verified`
  fact is set by the Provider verify path — the case is the internal source of truth,
  `verified` the boundary projection consumed by other contexts.

  This module is both the Ecto schema and the aggregate struct. The functional core
  below computes the case's invariants from its (preloaded) frozen steps and never
  consults the track policy after creation.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.Provider.ProviderProfile
  alias KlassHero.Provider.VerificationStep
  alias KlassHero.Provider.Vetting

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @entity_types [:individual, :business]
  @lifecycles [:not_started, :in_progress, :verified]

  schema "vetting_cases" do
    field :entity_type, Ecto.Enum, values: @entity_types
    field :lifecycle, Ecto.Enum, values: @lifecycles, default: :not_started

    belongs_to :provider, ProviderProfile,
      foreign_key: :provider_id,
      source: :provider_id,
      references: :id

    has_many :steps, VerificationStep, on_replace: :delete

    timestamps()
  end

  @type lifecycle :: :not_started | :in_progress | :verified
  @type t :: %__MODULE__{}

  @doc """
  Insert changeset for a freshly built case (from `new_for_track/2`), persisting the
  case and its frozen steps in one write. Uses `put_assoc` because the steps are
  already-built structs, not param maps.
  """
  def create_changeset(%__MODULE__{} = case_) do
    %__MODULE__{}
    |> change(%{
      id: case_.id,
      provider_id: case_.provider_id,
      entity_type: case_.entity_type,
      lifecycle: case_.lifecycle
    })
    |> put_assoc(:steps, case_.steps)
    |> unique_constraint(:provider_id)
    |> foreign_key_constraint(:provider_id)
  end

  @doc """
  Builds a new case for a Provider, freezing the steps of the track selected by
  `entity_type`.
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
  Approves the step with the given key (submitting it first if needed), recording the
  reviewer and evidence, then recomputes the lifecycle. Idempotent for an
  already-approved step.
  """
  @spec approve_step(t(), atom(), String.t(), String.t() | nil) :: {:ok, t()} | {:error, term()}
  def approve_step(%__MODULE__{} = case_, key, reviewer_id, evidence_ref) do
    with {:ok, step} <- fetch_step(case_, key) do
      approve_fetched_step(case_, step, reviewer_id, evidence_ref)
    end
  end

  defp approve_fetched_step(case_, step, reviewer_id, evidence_ref) do
    if VerificationStep.approved?(step) do
      {:ok, case_}
    else
      with {:ok, submitted} <- ensure_submitted(step),
           {:ok, approved} <- VerificationStep.approve(submitted, reviewer_id, evidence_ref) do
        {:ok, case_ |> replace_step(approved) |> recompute()}
      end
    end
  end

  @doc """
  Approves the step with the given key with no human reviewer (auto-approval driven by
  an external outcome, e.g. the Stripe Identity webhook), then recomputes the lifecycle.
  Idempotent for an already-approved step.
  """
  @spec auto_approve_step(t(), atom(), String.t() | nil) :: {:ok, t()} | {:error, term()}
  def auto_approve_step(%__MODULE__{} = case_, key, evidence_ref) do
    with {:ok, step} <- fetch_step(case_, key) do
      auto_approve_fetched_step(case_, step, evidence_ref)
    end
  end

  defp auto_approve_fetched_step(case_, step, evidence_ref) do
    if VerificationStep.approved?(step),
      do: {:ok, case_},
      else: apply_auto_approve(case_, step, evidence_ref)
  end

  defp apply_auto_approve(case_, step, evidence_ref) do
    with {:ok, approved} <- VerificationStep.auto_approve(step, evidence_ref) do
      {:ok, case_ |> replace_step(approved) |> recompute()}
    end
  end

  @doc """
  Rejects the step with the given key (submitting it first if needed) with a reason,
  then recomputes the lifecycle.
  """
  @spec reject_step(t(), atom(), String.t(), String.t()) :: {:ok, t()} | {:error, term()}
  def reject_step(%__MODULE__{} = case_, key, reviewer_id, reason) do
    with {:ok, step} <- fetch_step(case_, key),
         {:ok, submitted} <- ensure_submitted(step),
         {:ok, rejected} <- VerificationStep.reject(submitted, reviewer_id, reason) do
      {:ok, case_ |> replace_step(rejected) |> recompute()}
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
  Submits the step with the given key for review (from `:not_started` or `:rejected`),
  then recomputes the lifecycle. Used when a provider starts an out-of-band step (e.g.
  a Stripe Identity session) so the case reflects work in progress before the outcome
  arrives.
  """
  @spec submit_step(t(), atom()) :: {:ok, t()} | {:error, term()}
  def submit_step(%__MODULE__{} = case_, key) do
    with {:ok, step} <- fetch_step(case_, key),
         {:ok, submitted} <- VerificationStep.submit(step) do
      {:ok, case_ |> replace_step(submitted) |> recompute()}
    end
  end

  @doc "Finds the step completed via Stripe Identity, if the track has one."
  @spec step_key_for_identity(t()) :: atom() | nil
  def step_key_for_identity(%__MODULE__{steps: steps}) do
    Enum.find_value(steps, fn step ->
      if step.completed_via == {:stripe_identity}, do: step.key
    end)
  end

  @doc "Finds the step completed by signing an agreement of the given `kind`, if any."
  @spec step_key_for_signed_agreement(t(), atom()) :: atom() | nil
  def step_key_for_signed_agreement(%__MODULE__{steps: steps}, kind) do
    Enum.find_value(steps, fn step ->
      if step.completed_via == {:signed_agreement, kind}, do: step.key
    end)
  end

  @doc "Returns `true` when the track's Stripe Identity step exists and is approved."
  @spec identity_step_approved?(t()) :: boolean()
  def identity_step_approved?(%__MODULE__{steps: steps}) do
    Enum.any?(steps, fn step ->
      step.completed_via == {:stripe_identity} and step.status == :approved
    end)
  end

  @doc """
  Resets the step with the given key and every step that transitively depends on it (the
  reverse-edge closure of `requires`) back to `:not_started`, then recomputes the
  lifecycle.

  Powers two flows: a rejected document resets its own step (no dependents in the
  individual track), and a business responsible-person change resets identity, cascading
  to the steps that require it.
  """
  @spec reset_step(t(), atom()) :: {:ok, t()} | {:error, term()}
  def reset_step(%__MODULE__{} = case_, key) do
    with {:ok, _step} <- fetch_step(case_, key) do
      keys_to_reset = MapSet.put(dependent_keys(case_.steps, key), key)
      steps = Enum.map(case_.steps, &reset_if_member(&1, keys_to_reset))
      {:ok, recompute(%{case_ | steps: steps})}
    end
  end

  defp reset_if_member(step, keys_to_reset) do
    if MapSet.member?(keys_to_reset, step.key) do
      {:ok, reset} = VerificationStep.reset(step)
      reset
    else
      step
    end
  end

  # --- internals ---------------------------------------------------------------

  defp fetch_step(%__MODULE__{steps: steps}, key) do
    case Enum.find(steps, &(&1.key == key)) do
      nil -> {:error, :step_not_found}
      step -> {:ok, step}
    end
  end

  # Returns the set of step keys that transitively require `key` — every step that must
  # be reset when `key` is reset. Steps carry their frozen `requires` (direct
  # prerequisites); we need the reverse edges: the keys whose `requires` chain reaches
  # `key`. The target key itself is added by the caller, so it must NOT be in the
  # returned set. Implemented as a fixpoint: re-scan until a full pass adds nothing new.
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
