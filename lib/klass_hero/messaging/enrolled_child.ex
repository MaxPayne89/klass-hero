defmodule KlassHero.Messaging.EnrolledChild do
  @moduledoc """
  Read model for a child enrolled in a program — the `messaging_enrolled_children`
  table.

  Conventional Phoenix — this Ecto schema IS the struct that flows through
  Messaging's read paths. No changesets: the `EnrolledChildren` projection owns
  all writes, and reads return this struct directly.

  Exists so a conversation can render its enrolled child names without a
  synchronous call into Family or Enrollment.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: false}
  @timestamps_opts [type: :utc_datetime]

  schema "messaging_enrolled_children" do
    field :parent_user_id, :binary_id
    field :program_id, :binary_id
    field :child_id, :binary_id
    field :child_first_name, :string

    timestamps()
  end

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          parent_user_id: Ecto.UUID.t() | nil,
          program_id: Ecto.UUID.t() | nil,
          child_id: Ecto.UUID.t() | nil,
          child_first_name: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }
end
