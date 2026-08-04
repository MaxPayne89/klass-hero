defmodule KlassHero.Messaging.Conversation do
  @moduledoc """
  A messaging conversation: a direct 1-on-1 thread or a program broadcast.

  Conventional Phoenix — the Ecto schema is the struct that flows through the
  `KlassHero.Messaging` context; changesets are the single validation gatekeeper.
  `type` is an `Ecto.Enum`, so it loads/dumps as an atom without a mapper.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.Messaging.Message
  alias KlassHero.Messaging.Participant

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "conversations" do
    field :type, Ecto.Enum, values: [:direct, :program_broadcast]
    field :provider_id, :binary_id
    field :program_id, :binary_id
    field :subject, :string
    field :archived_at, :utc_datetime
    field :retention_until, :utc_datetime
    field :lock_version, :integer, default: 1

    # Virtual field populated by unread-count queries.
    field :unread_count, :integer, virtual: true, default: 0

    has_many :participants, Participant,
      foreign_key: :conversation_id,
      preload_order: [asc: :joined_at]

    has_many :messages, Message, foreign_key: :conversation_id

    timestamps()
  end

  @type conversation_type :: :direct | :program_broadcast

  @type t :: %__MODULE__{
          id: String.t(),
          type: conversation_type() | nil,
          provider_id: String.t(),
          program_id: String.t() | nil,
          subject: String.t() | nil,
          archived_at: DateTime.t() | nil,
          retention_until: DateTime.t() | nil,
          lock_version: integer(),
          unread_count: integer(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @required_fields ~w(type provider_id)a
  @optional_fields ~w(program_id subject archived_at retention_until lock_version)a

  @doc "Changeset for creating a conversation."
  def create_changeset(schema \\ %__MODULE__{}, attrs) do
    schema
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_broadcast_program_id()
    |> validate_length(:subject, max: 500)
    |> unique_constraint([:program_id],
      name: :conversations_active_broadcast_per_program,
      message: "Active broadcast already exists for this program"
    )
    |> foreign_key_constraint(:provider_id)
    |> foreign_key_constraint(:program_id)
    |> optimistic_lock(:lock_version)
  end

  defp validate_broadcast_program_id(changeset) do
    type = get_field(changeset, :type)
    program_id = get_field(changeset, :program_id)

    if type == :program_broadcast and is_nil(program_id) do
      add_error(changeset, :program_id, "is required for program broadcasts")
    else
      changeset
    end
  end
end
