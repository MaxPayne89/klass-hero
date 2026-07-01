defmodule KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.MessageSchema do
  @moduledoc """
  Ecto schema for the messages table.

  Use MessageMapper to convert between schema and domain Message entities.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.Accounts.User
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.ConversationSchema
  alias KlassHero.Messaging.Attachment

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  @valid_message_types ~w(text system)
  @max_content_length 10_000

  schema "messages" do
    field :conversation_id, :binary_id
    field :sender_id, :binary_id
    field :content, :string
    field :message_type, :string, default: "text"
    field :deleted_at, :utc_datetime

    belongs_to :conversation, ConversationSchema, define_field: false
    belongs_to :sender, User, foreign_key: :sender_id, define_field: false
    has_many :attachments, Attachment, foreign_key: :message_id

    timestamps()
  end

  @required_fields ~w(conversation_id sender_id)a
  @optional_fields ~w(content message_type deleted_at)a

  @doc """
  Creates a changeset for new message creation.

  Content is optional — a message may consist of attachments only.
  """
  def create_changeset(schema \\ %__MODULE__{}, attrs) do
    schema
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:message_type, @valid_message_types)
    |> validate_length(:content, max: @max_content_length)
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:sender_id)
  end

  @doc """
  Creates a changeset for soft deleting a message.
  """
  def delete_changeset(schema, attrs) do
    schema
    |> cast(attrs, [:deleted_at])
    |> validate_required([:deleted_at])
  end
end
