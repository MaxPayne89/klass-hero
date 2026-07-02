defmodule KlassHero.Messaging.Message do
  @moduledoc """
  A message within a conversation: a regular `:text` message or a `:system` note.

  Conventional Phoenix — the Ecto schema is the struct that flows through the
  `KlassHero.Messaging` context; changesets are the single validation gatekeeper.
  `message_type` is an `Ecto.Enum`, so it loads/dumps as an atom without a mapper.
  The "content or attachments" rule is enforced by the `send_message` use case, which
  orchestrates the message + its attachments together.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.Accounts.User
  alias KlassHero.Messaging.Attachment
  alias KlassHero.Messaging.Conversation

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  @max_content_length 10_000

  schema "messages" do
    field :conversation_id, :binary_id
    field :sender_id, :binary_id
    field :content, :string
    field :message_type, Ecto.Enum, values: [:text, :system], default: :text
    field :deleted_at, :utc_datetime

    belongs_to :conversation, Conversation, define_field: false
    belongs_to :sender, User, foreign_key: :sender_id, define_field: false
    has_many :attachments, Attachment, foreign_key: :message_id

    timestamps()
  end

  @type message_type :: :text | :system

  @type t :: %__MODULE__{
          id: String.t(),
          conversation_id: String.t(),
          sender_id: String.t(),
          content: String.t() | nil,
          message_type: message_type() | nil,
          deleted_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @required_fields ~w(conversation_id sender_id)a
  @optional_fields ~w(content message_type deleted_at)a

  @doc "Changeset for creating a message."
  def create_changeset(schema \\ %__MODULE__{}, attrs) do
    schema
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:content, max: @max_content_length)
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:sender_id)
  end

  @doc "Changeset for soft-deleting a message."
  def delete_changeset(schema, attrs) do
    schema
    |> cast(attrs, [:deleted_at])
    |> validate_required([:deleted_at])
  end
end
