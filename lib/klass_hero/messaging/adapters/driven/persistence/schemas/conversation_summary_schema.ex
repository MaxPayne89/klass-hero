defmodule KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.ConversationSummarySchema do
  @moduledoc """
  Ecto schema for the conversation_summaries read model table.

  This schema is write-only from the projection's perspective and
  read-only from the repository's perspective. No changesets for
  user-facing validation — the projection controls all writes.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: false}
  @timestamps_opts [type: :utc_datetime]

  schema "conversation_summaries" do
    field :conversation_id, :binary_id
    field :user_id, :binary_id
    field :conversation_type, :string
    field :provider_id, :binary_id
    field :program_id, :binary_id
    field :subject, :string
    field :other_participant_name, :string
    field :program_name, :string
    field :participant_count, :integer, default: 0
    field :latest_message_content, :string
    field :latest_message_sender_id, :binary_id
    field :latest_message_at, :utc_datetime
    field :unread_count, :integer, default: 0
    field :last_read_at, :utc_datetime
    field :archived_at, :utc_datetime
    field :has_attachments, :boolean, default: false
    field :system_notes, :map, default: %{}
    field :enrolled_child_names, {:array, :string}, default: []

    timestamps()
  end
end
