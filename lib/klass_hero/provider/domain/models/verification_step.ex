defmodule KlassHero.Provider.Domain.Models.VerificationStep do
  @moduledoc """
  One unit of a Vetting Case — a single Verification Step for a Provider.

  Frozen from a `StepDefinition` at case creation: the structural fields (`key`,
  `completed_via`, `requires`, `admin_review?`) are copied so a later track reordering never
  mutates an in-flight case. The step moves through a status lifecycle
  `:not_started → :submitted → :approved | :rejected`, and can be `reset/1` back to
  `:not_started` (e.g. when a business responsible person changes).

  Pure domain model — no persistence. Reconstituted from the DB via `from_persistence/1`.
  """

  use KlassHero.Shared.Domain.Models.PersistenceSupport

  alias KlassHero.Provider.Domain.Models.StepDefinition

  @valid_statuses [:not_started, :submitted, :approved, :rejected]

  @doc "Returns the list of valid step statuses."
  def valid_statuses, do: @valid_statuses

  @enforce_keys [:vetting_case_id, :key, :completed_via]
  defstruct [
    :id,
    :vetting_case_id,
    :key,
    :completed_via,
    :evidence_ref,
    :rejection_reason,
    :reviewed_by_id,
    :reviewed_at,
    :submitted_at,
    requires: [],
    admin_review?: false,
    status: :not_started
  ]

  @type status :: :not_started | :submitted | :approved | :rejected

  @type t :: %__MODULE__{
          id: String.t() | nil,
          vetting_case_id: String.t(),
          key: atom(),
          completed_via: StepDefinition.completed_via(),
          evidence_ref: String.t() | nil,
          rejection_reason: String.t() | nil,
          reviewed_by_id: String.t() | nil,
          reviewed_at: DateTime.t() | nil,
          submitted_at: DateTime.t() | nil,
          requires: [atom()],
          admin_review?: boolean(),
          status: status()
        }

  @doc """
  Freezes a `StepDefinition` into a `VerificationStep` instance for the given case,
  copying the structural fields and starting at `:not_started`.
  """
  @spec from_definition(StepDefinition.t(), String.t()) :: t()
  def from_definition(%StepDefinition{} = definition, vetting_case_id) do
    %__MODULE__{
      vetting_case_id: vetting_case_id,
      key: definition.key,
      completed_via: definition.completed_via,
      requires: definition.requires,
      admin_review?: definition.admin_review?,
      status: :not_started
    }
  end

  @doc "Returns true when the step is approved."
  def approved?(%__MODULE__{status: :approved}), do: true
  def approved?(%__MODULE__{}), do: false

  @doc """
  Submits a step for review. Allowed from `:not_started` or `:rejected` (resubmission).
  """
  def submit(%__MODULE__{status: status} = step) when status in [:not_started, :rejected] do
    {:ok, %{step | status: :submitted, submitted_at: now()}}
  end

  def submit(%__MODULE__{}), do: {:error, :step_not_startable}

  @doc """
  Approves a submitted step, recording the reviewer and the evidence reference.
  """
  def approve(%__MODULE__{status: :submitted} = step, reviewer_id, evidence_ref)
      when is_binary(reviewer_id) and byte_size(reviewer_id) > 0 do
    {:ok, %{step | status: :approved, reviewed_by_id: reviewer_id, reviewed_at: now(), evidence_ref: evidence_ref}}
  end

  def approve(%__MODULE__{status: :submitted}, _reviewer_id, _evidence_ref), do: {:error, :invalid_reviewer}
  def approve(%__MODULE__{}, _reviewer_id, _evidence_ref), do: {:error, :step_not_submitted}

  @doc """
  Approves a step with no human reviewer — for steps that auto-approve on an external outcome
  (e.g. the Stripe Identity webhook). Allowed from any non-approved state; `reviewed_by_id` is nil.
  """
  def auto_approve(%__MODULE__{status: status} = step, evidence_ref) when status != :approved do
    {:ok, %{step | status: :approved, reviewed_by_id: nil, reviewed_at: now(), evidence_ref: evidence_ref}}
  end

  def auto_approve(%__MODULE__{}, _evidence_ref), do: {:error, :step_already_approved}

  @doc """
  Rejects a submitted step with a reason.
  """
  def reject(%__MODULE__{status: :submitted} = step, reviewer_id, reason)
      when is_binary(reviewer_id) and byte_size(reviewer_id) > 0 and is_binary(reason) and byte_size(reason) > 0 do
    {:ok, %{step | status: :rejected, reviewed_by_id: reviewer_id, reviewed_at: now(), rejection_reason: reason}}
  end

  def reject(%__MODULE__{status: :submitted}, _reviewer_id, _reason), do: {:error, :invalid_review_params}
  def reject(%__MODULE__{}, _reviewer_id, _reason), do: {:error, :step_not_submitted}

  @doc """
  Resets a step back to `:not_started`, detaching evidence and clearing the review audit.
  The evidence record itself is retained elsewhere for audit; the step no longer claims it.
  """
  def reset(%__MODULE__{} = step) do
    {:ok,
     %{
       step
       | status: :not_started,
         evidence_ref: nil,
         rejection_reason: nil,
         reviewed_by_id: nil,
         reviewed_at: nil,
         submitted_at: nil
     }}
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
