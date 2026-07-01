defmodule KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.ConversationSchema do
  @moduledoc """
  Ecto schema for the conversations table.

  Use ConversationMapper to convert between schema and domain Conversation entities.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.MessageSchema
  alias KlassHero.Messaging.Participant

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  @valid_types ~w(direct program_broadcast)

  schema "conversations" do
    field :type, :string
    field :provider_id, :binary_id
    field :program_id, :binary_id
    field :subject, :string
    field :archived_at, :utc_datetime
    field :retention_until, :utc_datetime
    field :lock_version, :integer, default: 1

    # Virtual fields for query results
    field :unread_count, :integer, virtual: true, default: 0

    has_many :participants, Participant,
      foreign_key: :conversation_id,
      preload_order: [asc: :joined_at]

    has_many :messages, MessageSchema, foreign_key: :conversation_id

    timestamps()
  end

  @required_fields ~w(type provider_id)a
  @optional_fields ~w(program_id subject archived_at retention_until lock_version)a

  @doc """
  Creates a changeset for new conversation creation.
  """
  def create_changeset(schema \\ %__MODULE__{}, attrs) do
    schema
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:type, @valid_types)
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

  @doc """
  Creates a changeset for archiving a conversation.
  """
  def archive_changeset(schema, attrs) do
    schema
    |> cast(attrs, [:archived_at, :retention_until, :lock_version])
    |> validate_required([:archived_at, :retention_until])
    |> optimistic_lock(:lock_version)
  end

  defp validate_broadcast_program_id(changeset) do
    type = get_field(changeset, :type)
    program_id = get_field(changeset, :program_id)

    if type == "program_broadcast" and is_nil(program_id) do
      add_error(changeset, :program_id, "is required for program broadcasts")
    else
      changeset
    end
  end
end
