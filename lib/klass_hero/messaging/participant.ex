defmodule KlassHero.Messaging.Participant do
  @moduledoc """
  Conversation participant: membership and read receipts for a conversation.

  Conventional Phoenix — the Ecto schema is the struct that flows through the
  `KlassHero.Messaging` context; changesets are the single validation gatekeeper.
  Pure predicates (`active?/1`, `left?/1`, `has_unread?/2`) are the functional core.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.Accounts.User
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.ConversationSchema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "conversation_participants" do
    field :conversation_id, :binary_id
    field :user_id, :binary_id
    field :last_read_at, :utc_datetime
    field :joined_at, :utc_datetime
    field :left_at, :utc_datetime

    belongs_to :conversation, ConversationSchema, define_field: false
    belongs_to :user, User, define_field: false

    timestamps()
  end

  @type t :: %__MODULE__{
          id: String.t(),
          conversation_id: String.t(),
          user_id: String.t(),
          last_read_at: DateTime.t() | nil,
          joined_at: DateTime.t(),
          left_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @required_fields ~w(conversation_id user_id joined_at)a
  @optional_fields ~w(last_read_at left_at)a

  @doc "Changeset for adding a participant."
  def create_changeset(schema \\ %__MODULE__{}, attrs) do
    schema
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:conversation_id, :user_id])
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc "Changeset for marking messages as read."
  def mark_read_changeset(schema, attrs) do
    schema
    |> cast(attrs, [:last_read_at])
    |> validate_required([:last_read_at])
  end

  @doc "Changeset for leaving a conversation."
  def leave_changeset(schema, attrs) do
    schema
    |> cast(attrs, [:left_at])
    |> validate_required([:left_at])
  end

  @doc "True if the participant is active (has joined and not left)."
  @spec active?(t()) :: boolean()
  def active?(%__MODULE__{left_at: nil}), do: true
  def active?(%__MODULE__{}), do: false

  @doc "True if the participant has left the conversation."
  @spec left?(t()) :: boolean()
  def left?(%__MODULE__{left_at: nil}), do: false
  def left?(%__MODULE__{}), do: true

  @doc "True if the participant has unread messages given the latest message timestamp."
  @spec has_unread?(t(), DateTime.t() | nil) :: boolean()
  def has_unread?(%__MODULE__{last_read_at: nil}, nil), do: false
  def has_unread?(%__MODULE__{last_read_at: nil}, _latest_message_at), do: true

  def has_unread?(%__MODULE__{last_read_at: last_read_at}, latest_message_at) when not is_nil(latest_message_at) do
    DateTime.before?(last_read_at, latest_message_at)
  end

  def has_unread?(_, _), do: false
end
