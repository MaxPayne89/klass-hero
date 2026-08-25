defmodule KlassHero.Messaging.ListStaffConversations do
  @moduledoc """
  Lists conversations a provider owns but is not a participant of — chiefly the
  threads their staff conduct with parents (#746).

  The owner counterpart to `KlassHero.Messaging.MonitorConversations`, and the same
  shape: authorize first, read the write-side `conversations` table, stay strictly
  read-only. It creates no `Participant` row, writes no `last_read_at`, and
  subscribes to nothing.

  One behavioural difference from the admin list: threads the owner *is* in are
  excluded. Those already render as rich cards in their own inbox, so including them
  would show the same conversation twice across two tabs.

  ## Enrichment is batched

  Rows are enriched into `KlassHero.Messaging.StaffConversation` with **six queries
  per page — seven when the page holds a broadcast** — flat, regardless of page size.
  Nothing here runs per conversation.

  The staff lookup deserves a note: it uses
  `KlassHero.Provider.list_staff_user_ids_for_provider/1`, which returns everyone who
  has *ever* held a staff row, active or not. That is correct precisely because it
  feeds **display attribution** and never the gate — the use its own docstring
  sanctions. Naming a departed colleague on a thread they really did conduct is the
  desired behaviour; letting their departure hide the thread is not.
  """

  use KlassHero.Shared.Tracing

  alias KlassHero.Accounts
  alias KlassHero.Accounts.Scope
  alias KlassHero.Messaging.Authorization
  alias KlassHero.Messaging.Queries.ConversationQueries
  alias KlassHero.Messaging.Queries.MessageQueries
  alias KlassHero.Messaging.StaffConversation
  alias KlassHero.ProgramCatalog
  alias KlassHero.Repo

  @default_limit 25

  @doc """
  Returns a page of conversations, newest first.

  ## Options

    * `:type` - `:direct` or `:program_broadcast`
    * `:limit` - page size, defaults to #{@default_limit}
    * `:before` - exclusive `inserted_at` cursor for the next (older) page

  Authorization resolves before any option is read, so a non-owner's refusal cannot
  depend on what they asked for.
  """
  @spec execute(Scope.t(), keyword()) ::
          {:ok, [StaffConversation.t()], boolean()} | {:error, :unauthorized}
  def execute(%Scope{} = scope, opts \\ []) do
    span do
      with {:ok, provider_id} <- Authorization.authorize_provider_owner(scope) do
        OpenTelemetry.Tracer.set_attribute("messaging.staff_conversations.provider_id", provider_id)
        OpenTelemetry.Tracer.set_attribute("messaging.staff_conversations.owner_id", scope.user.id)

        list(scope.user.id, provider_id, opts)
      end
    end
  end

  defp list(owner_user_id, provider_id, opts) do
    limit = Keyword.get(opts, :limit, @default_limit)

    rows =
      ConversationQueries.base()
      |> ConversationQueries.by_provider(provider_id)
      |> ConversationQueries.where_user_is_not_participant(owner_user_id)
      |> ConversationQueries.active_only()
      |> maybe_by_type(Keyword.get(opts, :type))
      |> ConversationQueries.order_by_newest()
      |> ConversationQueries.paginate(Keyword.put(opts, :limit, limit))
      |> ConversationQueries.preload_assocs([:participants])
      |> Repo.all()

    page = Enum.take(rows, limit)

    {:ok, enrich(page, provider_id), length(rows) > limit}
  end

  defp maybe_by_type(query, nil), do: query
  defp maybe_by_type(query, type), do: ConversationQueries.by_type(query, type)

  defp enrich([], _provider_id), do: []

  defp enrich(conversations, provider_id) do
    latest_messages = latest_messages(conversations)

    context = %{
      user_names: user_names(conversations),
      staff_ids: staff_user_ids(provider_id),
      latest_messages: latest_messages,
      attachment_ids: attachment_ids(latest_messages),
      program_names: program_names(conversations)
    }

    Enum.map(conversations, &build_row(&1, context))
  end

  defp user_names(conversations) do
    conversations
    |> Enum.flat_map(fn conversation -> Enum.map(conversation.participants, & &1.user_id) end)
    |> Enum.uniq()
    |> Accounts.get_display_names()
  end

  defp staff_user_ids(provider_id) do
    acl_span source: "messaging", target: "provider" do
      provider_id
      |> KlassHero.Provider.list_staff_user_ids_for_provider()
      |> MapSet.new()
    end
  end

  defp latest_messages(conversations) do
    conversations
    |> Enum.map(& &1.id)
    |> MessageQueries.latest_per_conversation()
    |> Repo.all()
    |> Map.new(&{&1.conversation_id, &1})
  end

  defp attachment_ids(latest_messages) when map_size(latest_messages) == 0, do: MapSet.new()

  defp attachment_ids(latest_messages) do
    latest_messages
    |> Map.values()
    |> Enum.map(& &1.id)
    |> MessageQueries.message_ids_with_attachments()
    |> Repo.all()
    |> MapSet.new()
  end

  # Skips the query entirely when the page holds no broadcast — `get_titles/1` has an
  # empty-list clause, so this costs nothing on a page of direct threads.
  defp program_names(conversations) do
    for(
      %{type: :program_broadcast, program_id: id} <- conversations,
      not is_nil(id),
      uniq: true,
      do: id
    )
    |> ProgramCatalog.get_titles()
  end

  defp build_row(conversation, context) do
    active = Enum.filter(conversation.participants, &is_nil(&1.left_at))
    {staff, others} = Enum.split_with(active, &MapSet.member?(context.staff_ids, &1.user_id))
    latest = Map.get(context.latest_messages, conversation.id)

    %StaffConversation{
      conversation_id: conversation.id,
      conversation_type: conversation.type,
      provider_id: conversation.provider_id,
      program_id: conversation.program_id,
      program_name: broadcast_program_name(conversation, context.program_names),
      other_participant_name: other_participant_name(conversation.type, others, context.user_names),
      staff_member_names: named(staff, context.user_names),
      latest_message_content: latest && latest.content,
      latest_message_at: latest && latest.inserted_at,
      has_attachments: latest != nil and MapSet.member?(context.attachment_ids, latest.id),
      inserted_at: conversation.inserted_at
    }
  end

  defp broadcast_program_name(%{type: :program_broadcast, program_id: id}, names) when not is_nil(id) do
    Map.get(names, id)
  end

  defp broadcast_program_name(_conversation, _names), do: nil

  # A direct thread with anything other than exactly one non-staff party is ambiguous
  # (two staff DMing, or a parent who left). `nil` lets the card fall back to its own
  # "Unknown" rather than picking a party arbitrarily.
  defp other_participant_name(:direct, [%{user_id: id}], names), do: Map.get(names, id)
  defp other_participant_name(_type, _others, _names), do: nil

  defp named(participants, names) do
    participants
    |> Enum.map(&Map.get(names, &1.user_id))
    |> Enum.reject(&is_nil/1)
    |> Enum.sort()
  end
end
