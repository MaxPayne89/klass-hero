defmodule KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.ParticipantRepository do
  @moduledoc """
  Ecto-based repository for managing conversation participants.

  Implements ForManagingParticipants (writes) and ForQueryingParticipants (reads) ports.
  """

  @behaviour KlassHero.Messaging.Domain.Ports.ForManagingParticipants
  @behaviour KlassHero.Messaging.Domain.Ports.ForQueryingParticipants

  use KlassHero.Shared.Tracing

  import Ecto.Query

  alias KlassHero.Messaging.Adapters.Driven.Persistence.Mappers.ParticipantMapper
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.ParticipantSchema
  alias KlassHero.Repo

  require Logger

  @impl true
  def add(attrs) do
    span do
      set_attributes("db", operation: "insert", entity: "messaging_participant")

      schema_attrs = ParticipantMapper.to_create_attrs(attrs)

      %ParticipantSchema{}
      |> ParticipantSchema.create_changeset(schema_attrs)
      |> Repo.insert()
      |> case do
        {:ok, schema} ->
          participant = ParticipantMapper.to_domain(schema)

          Logger.debug("Added participant",
            participant_id: participant.id,
            conversation_id: participant.conversation_id,
            user_id: participant.user_id
          )

          {:ok, participant}

        {:error, %Ecto.Changeset{} = changeset} = result ->
          # Check specifically for unique constraint violation (already participant)
          case changeset.errors[:conversation_id] do
            {"has already been taken", _} -> {:error, :already_participant}
            _ -> result
          end
      end
    end
  end

  @impl true
  def add_or_get(attrs) do
    span do
      set_attributes("db", operation: "upsert", entity: "messaging_participant")

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      entry =
        attrs
        |> ParticipantMapper.to_create_attrs()
        |> Map.put(:id, Ecto.UUID.generate())
        |> Map.put(:joined_at, now)
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)

      case Repo.insert_all(ParticipantSchema, [entry],
             returning: true,
             on_conflict: :nothing,
             conflict_target: [:conversation_id, :user_id]
           ) do
        {1, [schema]} ->
          {:ok, ParticipantMapper.to_domain(schema)}

        # Trigger: row already existed; on_conflict: :nothing skipped the insert
        # Why: callers (BroadcastToProgram follow-up) need to keep going inside Repo.transaction
        #      without poisoning it via a unique-constraint failure
        # Outcome: fetch the existing row so the caller gets a Participant.t() either way
        {0, _} ->
          get(attrs.conversation_id, attrs.user_id)
      end
    end
  end

  @impl true
  def get(conversation_id, user_id) do
    span do
      set_attributes("db", operation: "select", entity: "messaging_participant")

      from(p in ParticipantSchema,
        where: p.conversation_id == ^conversation_id and p.user_id == ^user_id
      )
      |> Repo.one()
      |> case do
        nil -> {:error, :not_found}
        schema -> {:ok, ParticipantMapper.to_domain(schema)}
      end
    end
  end

  @impl true
  def list_for_conversation(conversation_id) do
    span do
      set_attributes("db", operation: "select", entity: "messaging_participant")

      from(p in ParticipantSchema,
        where: p.conversation_id == ^conversation_id and is_nil(p.left_at),
        order_by: [asc: p.joined_at]
      )
      |> Repo.all()
      |> Enum.map(&ParticipantMapper.to_domain/1)
    end
  end

  @impl true
  def mark_as_read(conversation_id, user_id, read_at) do
    span do
      set_attributes("db", operation: "update", entity: "messaging_participant")

      from(p in ParticipantSchema,
        where: p.conversation_id == ^conversation_id and p.user_id == ^user_id
      )
      |> Repo.one()
      |> case do
        nil ->
          {:error, :not_found}

        schema ->
          schema
          |> ParticipantSchema.mark_read_changeset(%{last_read_at: read_at})
          |> Repo.update()
          |> case do
            {:ok, updated} ->
              Logger.debug("Marked as read",
                conversation_id: conversation_id,
                user_id: user_id,
                read_at: read_at
              )

              {:ok, ParticipantMapper.to_domain(updated)}

            error ->
              error
          end
      end
    end
  end

  @impl true
  def leave(conversation_id, user_id) do
    span do
      set_attributes("db", operation: "update", entity: "messaging_participant")

      now = DateTime.utc_now()

      from(p in ParticipantSchema,
        where: p.conversation_id == ^conversation_id and p.user_id == ^user_id
      )
      |> Repo.one()
      |> case do
        nil ->
          {:error, :not_found}

        schema ->
          schema
          |> ParticipantSchema.leave_changeset(%{left_at: now})
          |> Repo.update()
          |> case do
            {:ok, updated} ->
              Logger.info("Participant left conversation",
                conversation_id: conversation_id,
                user_id: user_id
              )

              {:ok, ParticipantMapper.to_domain(updated)}

            error ->
              error
          end
      end
    end
  end

  @impl true
  def is_participant?(conversation_id, user_id) do
    span do
      set_attributes("db", operation: "select", entity: "messaging_participant")

      from(p in ParticipantSchema,
        where:
          p.conversation_id == ^conversation_id and
            p.user_id == ^user_id and
            is_nil(p.left_at)
      )
      |> Repo.exists?()
    end
  end

  @impl true
  def mark_all_as_left(user_id) do
    span do
      set_attributes("db", operation: "update", entity: "messaging_participant")

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {count, _} =
        from(p in ParticipantSchema,
          where: p.user_id == ^user_id and is_nil(p.left_at)
        )
        |> Repo.update_all(set: [left_at: now])

      Logger.debug("Marked all participations as left for user",
        user_id: user_id,
        count: count
      )

      {:ok, count}
    end
  rescue
    e in DBConnection.ConnectionError ->
      Logger.error("Database connection error marking participations as left",
        user_id: user_id,
        error: Exception.message(e)
      )

      {:error, :database_connection_error}

    e in Postgrex.Error ->
      Logger.error("Database query error marking participations as left",
        user_id: user_id,
        error: Exception.message(e)
      )

      {:error, :database_query_error}
  end

  @impl true
  def add_batch(conversation_id, user_ids) do
    span do
      set_attributes("db", operation: "insert", entity: "messaging_participant")

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      entries =
        Enum.map(user_ids, fn user_id ->
          %{
            id: Ecto.UUID.generate(),
            conversation_id: conversation_id,
            user_id: user_id,
            joined_at: now,
            inserted_at: now,
            updated_at: now
          }
        end)

      {_count, schemas} =
        Repo.insert_all(ParticipantSchema, entries,
          returning: true,
          on_conflict: :nothing,
          conflict_target: [:conversation_id, :user_id]
        )

      participants = Enum.map(schemas, &ParticipantMapper.to_domain/1)

      Logger.debug("Added batch of participants",
        conversation_id: conversation_id,
        count: length(participants)
      )

      {:ok, participants}
    end
  end

  @impl true
  def add_to_conversations_batch(_user_id, []), do: {:ok, 0}

  def add_to_conversations_batch(user_id, conversation_ids) do
    span do
      set_attributes("db", operation: "insert", entity: "messaging_participant")

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      entries =
        Enum.map(conversation_ids, fn conversation_id ->
          %{
            id: Ecto.UUID.generate(),
            conversation_id: conversation_id,
            user_id: user_id,
            joined_at: now,
            inserted_at: now,
            updated_at: now
          }
        end)

      {count, _} =
        Repo.insert_all(ParticipantSchema, entries,
          on_conflict: :nothing,
          conflict_target: [:conversation_id, :user_id]
        )

      Logger.debug("Added staff user to conversations in batch",
        user_id: user_id,
        conversation_count: length(conversation_ids),
        added_count: count
      )

      {:ok, count}
    end
  end
end
