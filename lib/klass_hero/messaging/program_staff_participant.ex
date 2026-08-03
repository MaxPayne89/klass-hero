defmodule KlassHero.Messaging.ProgramStaffParticipant do
  @moduledoc """
  Messaging's local record of which staff are active on a program — the
  `program_staff_participants` table. Source of truth is Provider's
  `program_staff_assignments`; this mirror is kept current by integration events.

  Unlike Messaging's projection read models (`ConversationSummary`,
  `EnrolledChild`), this schema **has a changeset**: no projection GenServer owns
  the table, so `StaffParticipants` writes it directly from an event handler and
  needs the validation and unique constraint. Don't copy this shape for a table a
  projection maintains — those take no changeset at all.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "program_staff_participants" do
    field :provider_id, :binary_id
    field :program_id, :binary_id
    field :staff_user_id, :binary_id
    field :active, :boolean, default: true

    timestamps()
  end

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          provider_id: Ecto.UUID.t() | nil,
          program_id: Ecto.UUID.t() | nil,
          staff_user_id: Ecto.UUID.t() | nil,
          active: boolean(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @required_fields ~w(provider_id program_id staff_user_id)a
  @optional_fields ~w(active)a

  def changeset(schema \\ %__MODULE__{}, attrs) do
    schema
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:program_id, :staff_user_id])
  end
end
