defmodule KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.ConversationSummariesRepository do
  @moduledoc """
  Repository for the conversation_summaries denormalized read model.

  Handles reads (listing, counting, existence checks) and synchronous
  write-throughs (system note tokens). Bulk writes are handled by the
  ConversationSummaries projection.
  """

  @behaviour KlassHero.Messaging.Domain.Ports.ForManagingConversationSummaries
  @behaviour KlassHero.Messaging.Domain.Ports.ForQueryingConversationSummaries

  use KlassHero.Shared.Interaction

  import Ecto.Query

  alias KlassHero.Messaging.Adapters.Driven.Persistence.Queries.ConversationSummaryQueries
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.ConversationSchema
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.ConversationSummarySchema
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.ParticipantSchema
  alias KlassHero.Messaging.Domain.ReadModels.ConversationSummary
  alias KlassHero.Repo

  require Logger

  @default_limit 25

  @impl true
  def list_for_user(user_id, opts) do
    db_interaction operation: :list_for_user, entity: "conversation_summary" do
      limit = Keyword.get(opts, :limit, @default_limit)

      Logger.debug("[ConversationSummariesRepository] Listing summaries for user",
        user_id: user_id,
        limit: limit
      )

      # Fetch limit+1 to detect next page without a separate COUNT query.
      schemas =
        from(s in ConversationSummarySchema,
          where: s.user_id == ^user_id and is_nil(s.archived_at),
          order_by: [desc: s.latest_message_at, desc: s.id],
          limit: ^(limit + 1)
        )
        |> Repo.all()

      {items, has_more} =
        if length(schemas) > limit do
          {Enum.take(schemas, limit), true}
        else
          {schemas, false}
        end

      summaries = Enum.map(items, &to_dto/1)

      Logger.debug("[ConversationSummariesRepository] Retrieved summaries",
        user_id: user_id,
        returned_count: length(summaries),
        has_more: has_more
      )

      {:ok, summaries, has_more}
    end
  end

  @impl true
  def get_total_unread_count(user_id) do
    db_interaction operation: :get_total_unread_count, entity: "conversation_summary" do
      Logger.debug("[ConversationSummariesRepository] Getting total unread count",
        user_id: user_id
      )

      count =
        from(s in ConversationSummarySchema,
          where: s.user_id == ^user_id and is_nil(s.archived_at),
          select: coalesce(sum(s.unread_count), 0)
        )
        |> Repo.one()

      Logger.debug("[ConversationSummariesRepository] Total unread count",
        user_id: user_id,
        count: count
      )

      count
    end
  end

  @impl true
  def has_system_note?(conversation_id, token) do
    db_interaction operation: :has_system_note, entity: "conversation_summary" do
      ConversationSummaryQueries.base()
      |> ConversationSummaryQueries.by_conversation(conversation_id)
      |> ConversationSummaryQueries.has_system_note_key(token)
      |> Repo.exists?()
    end
  end

  @impl true
  def write_system_note_token(conversation_id, token) do
    db_interaction operation: :write_system_note_token, entity: "conversation_summary" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      token_json = %{token => DateTime.to_iso8601(now)}

      {updated, _} =
        from(s in ConversationSummarySchema,
          where: s.conversation_id == ^conversation_id,
          update: [
            set: [
              system_notes:
                fragment(
                  "coalesce(system_notes, '{}')::jsonb || ?::jsonb",
                  ^token_json
                ),
              updated_at: ^now
            ]
          ]
        )
        |> Repo.update_all([])

      # Summary rows are created asynchronously by the projection. If write-through
      # races ahead of the projection, seed minimal rows so the token isn't lost;
      # the projection's upsert merges remaining fields when it catches up.
      if updated == 0 do
        seed_summary_rows_with_token(conversation_id, token_json, now)
      end

      :ok
    end
  end

  defp seed_summary_rows_with_token(conversation_id, token_json, now) do
    conversation =
      from(c in ConversationSchema,
        where: c.id == ^conversation_id,
        select: %{type: c.type, provider_id: c.provider_id, subject: c.subject}
      )
      |> Repo.one()

    participant_user_ids =
      from(p in ParticipantSchema,
        where: p.conversation_id == ^conversation_id and is_nil(p.left_at),
        select: p.user_id
      )
      |> Repo.all()

    cond do
      is_nil(conversation) ->
        Logger.warning(
          "seed_summary_rows_with_token: conversation not found, projection will handle",
          conversation_id: conversation_id
        )

      participant_user_ids == [] ->
        Logger.warning(
          "seed_summary_rows_with_token: no active participants, projection will handle",
          conversation_id: conversation_id
        )

      true ->
        entries =
          Enum.map(participant_user_ids, fn user_id ->
            %{
              id: Ecto.UUID.generate(),
              conversation_id: conversation_id,
              user_id: user_id,
              conversation_type: conversation.type,
              provider_id: conversation.provider_id,
              subject: conversation.subject,
              system_notes: token_json,
              unread_count: 0,
              participant_count: length(participant_user_ids),
              inserted_at: now,
              updated_at: now
            }
          end)

        # JSONB || merge: {:replace, [:system_notes]} would overwrite tokens the
        # projection already wrote between our update_all and this insert_all.
        Repo.insert_all(ConversationSummarySchema, entries,
          on_conflict:
            from(s in ConversationSummarySchema,
              update: [
                set: [
                  system_notes:
                    fragment(
                      "coalesce(?.system_notes, '{}')::jsonb || excluded.system_notes::jsonb",
                      s
                    ),
                  updated_at: fragment("excluded.updated_at")
                ]
              ]
            ),
          conflict_target: [:conversation_id, :user_id]
        )
    end
  end

  @impl true
  def get_conversation_context(conversation_id, user_id) do
    db_interaction operation: :get_conversation_context, entity: "conversation_summary" do
      result =
        from(s in ConversationSummarySchema,
          where: s.conversation_id == ^conversation_id and s.user_id == ^user_id,
          select: %{
            enrolled_child_names: s.enrolled_child_names,
            other_participant_name: s.other_participant_name
          }
        )
        |> Repo.one()

      case result do
        nil ->
          %{enrolled_child_names: [], other_participant_name: nil}

        %{enrolled_child_names: names, other_participant_name: other} ->
          %{enrolled_child_names: names || [], other_participant_name: other}
      end
    end
  end

  defp to_dto(%ConversationSummarySchema{} = schema) do
    ConversationSummary.new(%{
      id: schema.id,
      conversation_id: schema.conversation_id,
      user_id: schema.user_id,
      conversation_type: schema.conversation_type,
      provider_id: schema.provider_id,
      program_id: schema.program_id,
      subject: schema.subject,
      other_participant_name: schema.other_participant_name,
      program_name: schema.program_name,
      participant_count: schema.participant_count,
      latest_message_content: schema.latest_message_content,
      latest_message_sender_id: schema.latest_message_sender_id,
      latest_message_at: schema.latest_message_at,
      has_attachments: schema.has_attachments,
      unread_count: schema.unread_count,
      last_read_at: schema.last_read_at,
      archived_at: schema.archived_at,
      enrolled_child_names: schema.enrolled_child_names || [],
      inserted_at: schema.inserted_at,
      updated_at: schema.updated_at
    })
  end
end
