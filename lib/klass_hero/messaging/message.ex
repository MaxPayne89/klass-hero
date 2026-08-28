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

  alias KlassHero.Messaging.Attachment
  alias KlassHero.Messaging.Conversation

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @max_content_length 10_000

  schema "messages" do
    field :conversation_id, :binary_id
    field :sender_id, :binary_id
    field :content, :string
    field :message_type, Ecto.Enum, values: [:text, :system], default: :text
    field :sender_role, Ecto.Enum, values: [:provider, :staff, :parent]
    field :deleted_at, :utc_datetime

    belongs_to :conversation, Conversation, define_field: false
    has_many :attachments, Attachment, foreign_key: :message_id

    timestamps()
  end

  @type message_type :: :text | :system
  @type sender_role :: :provider | :staff | :parent

  @type t :: %__MODULE__{
          id: String.t(),
          conversation_id: String.t(),
          sender_id: String.t(),
          content: String.t() | nil,
          message_type: message_type() | nil,
          sender_role: sender_role() | nil,
          deleted_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @required_fields ~w(conversation_id sender_id)a
  @optional_fields ~w(content message_type sender_role deleted_at)a

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

  @doc """
  Whether the message was sent from the provider's side, i.e. whether it renders
  with branded attribution ("Business via Staff Name").

  Answered from `sender_role`, recorded when the message was written, so it stays
  true to the moment of sending: deactivating or unassigning a staff member cannot
  restyle messages they sent while employed (#1348).

  `sender_role` is `nil` on rows written before that column existed. Those fall
  back to `fallback_provider_user_ids` — the live provider-side set the render path
  used before #1348 — which is the only signal available for them. The fallback
  expires with the rows: `EnforceRetentionPolicy` deletes messages past retention,
  so both it and the set can go once none survive.
  """
  @spec provider_side?(t(), MapSet.t(String.t()) | nil) :: boolean()
  def provider_side?(message, fallback_provider_user_ids \\ nil)

  def provider_side?(%__MODULE__{sender_role: role}, _fallback) when role in [:provider, :staff], do: true

  def provider_side?(%__MODULE__{sender_role: role}, _fallback) when not is_nil(role), do: false

  def provider_side?(%__MODULE__{sender_id: sender_id}, %MapSet{} = fallback), do: MapSet.member?(fallback, sender_id)

  def provider_side?(%__MODULE__{}, _fallback), do: false
end
