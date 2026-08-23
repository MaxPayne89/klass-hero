defmodule KlassHero.Participation.AttendanceTransition do
  @moduledoc """
  One recorded change of a `ParticipationRecord`'s status — who made it, when,
  and why.

  A sidecar to the record, not a replacement: `participation_records.status`
  stays authoritative. This table answers what a column cannot, because a column
  holds only the latest value and an attendance history is a sequence (#1329).

  Every attendance verb appends here through the single write path in
  `KlassHero.Participation` that all of them share. That is deliberate rather
  than incidental: a check-in also writes `check_in_at`/`check_in_by` on the
  record, so the same fact lives in two places, and keeping both writes inside
  one function is what stops them disagreeing.

  A NULL `actor_id` carries meaning — no human did this. It marks the batch
  absence that session completion applies to every still-registered child, and
  is how an automatic absence is told from a deliberate one.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.Participation.ParticipationRecord

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses [:registered, :checked_in, :checked_out, :absent]

  schema "attendance_transitions" do
    field :record_id, :binary_id
    field :from_status, Ecto.Enum, values: @statuses
    field :to_status, Ecto.Enum, values: @statuses
    field :actor_id, :binary_id
    field :reason, :string
    field :occurred_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{}

  @required_fields [:record_id, :from_status, :to_status, :occurred_at]
  @optional_fields [:actor_id, :reason]

  @doc """
  Builds the transition between two states of the same record.

  Takes both states rather than a `from`/`to` status pair: a pair lets a caller
  record a direction it did not make, two structs cannot.
  """
  @spec between(ParticipationRecord.t(), ParticipationRecord.t(), String.t() | nil, String.t() | nil) ::
          Ecto.Changeset.t()
  def between(%ParticipationRecord{} = before, %ParticipationRecord{} = later, actor_id, reason) do
    changeset(%__MODULE__{}, %{
      record_id: later.id,
      from_status: before.status,
      to_status: later.status,
      actor_id: actor_id,
      reason: reason,
      # When the status changed — which is now, even for a correction that
      # asserts an arrival time hours in the past. Deriving this from the
      # record's own `check_in_at` would agree on the forward verbs and lie on
      # `correct_attendance/3`, where that column is admin-editable.
      occurred_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = transition, attrs) do
    transition
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
