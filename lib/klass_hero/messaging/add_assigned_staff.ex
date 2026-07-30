defmodule KlassHero.Messaging.AddAssignedStaff do
  @moduledoc """
  Adds active staff assigned to a program as participants of a conversation
  and **returns** a `:participant_added` domain event for the caller to
  dispatch *after* the enclosing transaction commits.

  ## Why return the event instead of dispatching it?

  The `ConversationSummaries` projection runs in its own GenServer on its
  own DB connection. Under PostgreSQL READ COMMITTED isolation it cannot
  see uncommitted writes, so it must not run before the conversation row
  commits. This command therefore returns its events as data; the caller
  stages them through `Outbox.transact/2`, and the delivery job runs after
  the commit.

  ## Returns

  - `{:ok, {added_user_ids, events}}` — `events` is a list of zero or one
    `Event` structs. Empty when no eligible staff exist or when
    `program_id` is `nil`.
  - `{:error, reason}` — when the participant batch insert fails.
  """

  alias KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.ProgramStaffParticipantRepository
  alias KlassHero.Messaging.Domain.Events.MessagingEvents
  alias KlassHero.Shared.Domain.Events.Event

  @spec execute(String.t(), String.t() | nil, String.t()) ::
          {:ok, {[String.t()], [Event.t()]}} | {:error, term()}
  def execute(_conversation_id, nil, _excluded_user_id), do: {:ok, {[], []}}

  def execute(conversation_id, program_id, excluded_user_id) do
    program_id
    |> ProgramStaffParticipantRepository.get_active_staff_user_ids()
    |> Enum.reject(&(&1 == excluded_user_id))
    |> add(conversation_id)
  end

  defp add([], _conversation_id), do: {:ok, {[], []}}

  defp add(ids, conversation_id) do
    with {:ok, _} <- KlassHero.Messaging.add_participants(conversation_id, ids) do
      event = MessagingEvents.participant_added(conversation_id, ids, :initial_staff)
      {:ok, {ids, [event]}}
    end
  end
end
