defmodule KlassHero.Provider.VerificationStep do
  @moduledoc """
  One unit of a Vetting Case — a single Verification Step for a Provider
  (`verification_steps` table).

  Frozen from a `StepDefinition` at case creation: the structural fields (`key`,
  `completed_via`, `requires`, `admin_review`) are copied so a later track reordering
  never mutates an in-flight case. The step moves through a status lifecycle
  `:not_started → :submitted → :approved | :rejected`, and can be `reset/1` back to
  `:not_started` (e.g. when a business responsible person changes).

  This module is both the Ecto schema and the struct consumers pattern-match. The
  `completed_via` tuple and the atom `key`/`requires` are bridged to their string
  columns by the custom `CompletedVia`/`StepKey` types, so the pure transition
  functions below (the functional core) operate on the loaded struct unchanged.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.Accounts.User
  alias KlassHero.Provider.StepDefinition
  alias KlassHero.Provider.Types.CompletedVia
  alias KlassHero.Provider.Types.StepKey
  alias KlassHero.Provider.VettingCase

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @statuses [:not_started, :submitted, :approved, :rejected]

  schema "verification_steps" do
    field :key, StepKey
    field :completed_via, CompletedVia
    field :status, Ecto.Enum, values: @statuses, default: :not_started
    field :requires, {:array, StepKey}, default: []
    field :admin_review, :boolean, default: false
    field :evidence_ref, :binary_id
    field :rejection_reason, :string
    field :reviewed_at, :utc_datetime_usec
    field :submitted_at, :utc_datetime_usec

    belongs_to :vetting_case, VettingCase
    belongs_to :reviewed_by, User

    timestamps()
  end

  @type status :: :not_started | :submitted | :approved | :rejected
  @type t :: %__MODULE__{}

  @doc "Returns the list of valid step statuses."
  @spec valid_statuses() :: [status()]
  def valid_statuses, do: @statuses

  @doc """
  Changeset for persisting a step's mutable state as part of its Vetting Case
  (via `cast_assoc`). The structural fields are frozen at creation; the transition
  functions are the gatekeeper for status changes, so this casts the audit fields.
  """
  def changeset(%__MODULE__{} = step, attrs) do
    step
    |> cast(attrs, ~w(id key completed_via status requires admin_review evidence_ref
                      rejection_reason reviewed_by_id reviewed_at submitted_at)a)
    |> validate_required(~w(key completed_via status)a)
    |> foreign_key_constraint(:reviewed_by_id)
  end

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
      admin_review: definition.admin_review,
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
  Approves a step with no human reviewer — for steps that auto-approve on an external
  outcome (e.g. the Stripe Identity webhook). Allowed from any non-approved state.
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
