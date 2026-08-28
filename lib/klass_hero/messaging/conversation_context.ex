defmodule KlassHero.Messaging.ConversationContext do
  @moduledoc """
  Who a conversation is *with*, and which children it is *about*.

  Two facts, derived together because they are derived from the same two reads: the
  display names of everyone involved, and the roster of the program a direct thread
  hangs off. Both are what a conversation is titled by — "Sarah for Emma, Liam" — on
  an inbox card and on the thread page alike.

  ## Why a module rather than two private functions

  It was two private functions, in `ListConversations`, and a second implementation
  of the same derivation in `Messaging.get_conversation_summary_context/2` reading
  the retired `conversation_summaries` table. Two implementations of one derivation
  drifting apart is precisely what ADR-0023 retired projections over, so the second
  occurrence gets extracted rather than copied (CLAUDE.md, "Second Occurrence
  Escalates").

  ## Why batch-shaped

  `for_conversations/2` takes a list because the inbox needs a page's worth and a
  per-row API cannot serve one without becoming the N+1 the live read exists to
  avoid. The single-conversation caller passes a one-element list; that costs it two
  queries, exactly what the row it used to read cost.

  Callers pass conversations with `:participants` preloaded. The result is total over
  the input — every conversation gets an entry, empty where nothing applies — so
  `Map.fetch!/2` is safe.

  ## Who sees a name

  Only a principal of the thread, or someone currently seated in it. A provider owner
  looking at a staff member's thread is neither, and gets the empty context, which is
  what titles that thread generically. That used to fall out of the read table's
  `(conversation_id, user_id)` key having no row for them; derived live it has to be
  stated, because the principals are right there. Whether the owner *should* see the
  parent's name is #1523, and this is the line to move.
  """

  use KlassHero.Shared.Tracing

  import Ecto.Query

  alias KlassHero.Accounts
  alias KlassHero.Messaging.Conversation
  alias KlassHero.Repo

  @type context :: %{enrolled_child_names: [String.t()], other_participant_name: String.t() | nil}

  @empty %{enrolled_child_names: [], other_participant_name: nil}

  @doc """
  Titling context for each conversation, keyed by conversation id.

  Two batched reads for the whole list: display names via `Accounts`, and the
  enrolled-child roster via a direct read of Enrollment's tables.
  """
  @spec for_conversations([Conversation.t()], String.t()) :: %{String.t() => context()}
  def for_conversations([], _viewer_id), do: %{}

  def for_conversations(conversations, viewer_id) do
    lookups = %{
      viewer_id: viewer_id,
      user_names: user_names(conversations),
      child_names: child_names(conversations)
    }

    Map.new(conversations, &{&1.id, build(&1, lookups)})
  end

  defp build(conversation, lookups) do
    if visible_to?(conversation, lookups.viewer_id) do
      %{
        enrolled_child_names: enrolled_child_names(conversation, lookups),
        other_participant_name: other_participant_name(conversation, lookups)
      }
    else
      @empty
    end
  end

  defp visible_to?(conversation, viewer_id) do
    viewer_id in [conversation.principal_a_id, conversation.principal_b_id] or
      Enum.any?(conversation.participants, &(is_nil(&1.left_at) and &1.user_id == viewer_id))
  end

  defp user_names(conversations) do
    conversations
    |> Enum.flat_map(fn c -> Enum.map(c.participants, & &1.user_id) end)
    |> Enum.uniq()
    |> Accounts.get_display_names()
  end

  # The children a direct thread is about, keyed by {program_id, parent identity}.
  # Status-agnostic on purpose beyond pending/confirmed: a cancelled enrollment stops
  # being part of the thread's subject.
  defp child_names(conversations) do
    program_ids =
      for(%{type: :direct, program_id: id} <- conversations, not is_nil(id), uniq: true, do: id)

    user_ids =
      for(
        %{type: :direct, program_id: id} = c <- conversations,
        not is_nil(id),
        participant <- c.participants,
        uniq: true,
        do: participant.user_id
      )

    fetch_child_names(program_ids, user_ids)
  end

  defp fetch_child_names([], _user_ids), do: %{}
  defp fetch_child_names(_program_ids, []), do: %{}

  defp fetch_child_names(program_ids, user_ids) do
    acl_span source: "messaging", target: "enrollment" do
      from(e in "enrollments",
        join: c in "children",
        on: c.id == e.child_id,
        join: pp in "parents",
        on: pp.id == e.parent_id,
        where:
          e.status in ["pending", "confirmed"] and
            e.program_id in type(^program_ids, {:array, :binary_id}) and
            pp.identity_id in type(^user_ids, {:array, :binary_id}) and
            not is_nil(c.first_name),
        select: {
          type(e.program_id, :binary_id),
          type(pp.identity_id, :binary_id),
          c.first_name
        },
        distinct: true
      )
      |> Repo.all()
      |> Enum.group_by(fn {program_id, user_id, _name} -> {program_id, user_id} end, &elem(&1, 2))
      |> Map.new(fn {key, names} -> {key, Enum.sort(names)} end)
    end
  end

  # Read off the principals rather than the participant list: a thread seats assigned
  # staff too, and a parent who has left stops being a participant while remaining who
  # the thread is with.
  defp other_participant_name(%{type: :direct} = conversation, lookups) do
    [conversation.principal_a_id, conversation.principal_b_id]
    |> Enum.reject(&(is_nil(&1) or &1 == lookups.viewer_id))
    |> case do
      [other | _] -> Map.get(lookups.user_names, other)
      [] -> fallback_participant_name(conversation, lookups)
    end
  end

  defp other_participant_name(_conversation, _lookups), do: nil

  # Threads predating the principal pair (#747) carry neither principal, so the only
  # answer left is the other active participant.
  defp fallback_participant_name(conversation, lookups) do
    conversation.participants
    |> Enum.filter(&(is_nil(&1.left_at) and &1.user_id != lookups.viewer_id))
    |> Enum.find_value(&Map.get(lookups.user_names, &1.user_id))
  end

  defp enrolled_child_names(%{type: :direct, program_id: program_id} = conversation, lookups)
       when not is_nil(program_id) do
    conversation.participants
    |> Enum.flat_map(&Map.get(lookups.child_names, {program_id, &1.user_id}, []))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp enrolled_child_names(_conversation, _lookups), do: []
end
