defmodule KlassHero.Messaging.RemoveAssignedStaff do
  @moduledoc """
  Removes a staff member from every active conversation of a program and
  **returns** one `:participant_removed` domain event per affected
  conversation for the caller to dispatch *after* the enclosing
  transaction commits.

  ## Why events-as-data?

  The `ConversationSummaries` projection reads from the DB on a separate
  connection. To uphold read-your-own-writes, dispatches must occur after
  `Repo.transaction` returns `{:ok, _}`. See
  `KlassHero.Messaging.AddAssignedStaff` for the
  symmetric add command and the architectural rationale.

  ## Returns

  - `{:ok, {removals, events}}` — `removals` is a list of
    `%{conversation_id: String.t()}`. `events` pairs 1-to-1 with
    `removals` in the same order.
  - `{:error, reason}` — when a `leave` write fails.
  """

  alias KlassHero.Messaging.Events
  alias KlassHero.Shared.Domain.Events.Event

  @type removal :: %{conversation_id: String.t()}

  @spec execute(String.t(), String.t()) ::
          {:ok, {[removal()], [Event.t()]}} | {:error, term()}
  def execute(program_id, staff_user_id) do
    program_id
    |> KlassHero.Messaging.list_active_program_conversation_ids_with_participant(staff_user_id)
    |> remove_each(staff_user_id, [], [])
  end

  defp remove_each([], _staff_user_id, removals, events), do: {:ok, {Enum.reverse(removals), Enum.reverse(events)}}

  defp remove_each([conversation_id | rest], staff_user_id, removals, events) do
    with {:ok, _participant} <- KlassHero.Messaging.leave_conversation(conversation_id, staff_user_id) do
      event =
        Events.participant_removed(
          conversation_id,
          [staff_user_id],
          :staff_unassignment
        )

      remove_each(
        rest,
        staff_user_id,
        [%{conversation_id: conversation_id} | removals],
        [event | events]
      )
    end
  end
end
