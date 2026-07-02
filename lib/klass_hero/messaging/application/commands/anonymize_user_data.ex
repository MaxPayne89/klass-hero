defmodule KlassHero.Messaging.Application.Commands.AnonymizeUserData do
  @moduledoc """
  Use case for anonymizing a user's messaging data as part of GDPR deletion.

  Replaces message content with `"[deleted]"` and marks all active
  conversation participations as left. Dispatches a `user_data_anonymized`
  domain event on success — registered handlers promote it to an integration
  event for cross-context notification.

  Full GDPR-compliant anonymization of the user identity is performed by the
  Accounts context. This use case handles the Messaging context's portion of that cascade.
  """

  alias KlassHero.Messaging.Domain.Events.MessagingEvents
  alias KlassHero.Repo
  alias KlassHero.Shared.DomainEventBus

  require Logger

  @context KlassHero.Messaging

  @doc """
  Anonymizes all messaging data for a user.

  All database operations run in a single transaction to prevent partial
  anonymization (e.g. messages anonymized but participations still active).
  The domain event is dispatched after commit — handlers (integration event
  promotion, etc.) run in this process.

  ## Parameters

  - `user_id` - The ID of the user to anonymize

  ## Returns

  - `{:ok, %{messages_anonymized: n, participants_updated: n}}` - Success
  - `{:error, reason}` - Failure at any step
  """
  @spec execute(binary()) :: {:ok, map()} | {:error, term()}
  def execute(user_id) do
    user_id
    |> run_anonymization_transaction()
    |> handle_result(user_id)
  end

  defp run_anonymization_transaction(user_id) do
    Repo.transaction(fn ->
      with {:ok, msg_count} <-
             tag_step(:anonymize_messages, KlassHero.Messaging.anonymize_messages_for_sender(user_id)),
           {:ok, part_count} <-
             tag_step(:mark_as_left, KlassHero.Messaging.mark_all_participations_left(user_id)) do
        %{messages_anonymized: msg_count, participants_updated: part_count}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp tag_step(_step, {:ok, _} = result), do: result
  defp tag_step(step, {:error, reason}), do: {:error, {step, reason}}

  defp handle_result({:ok, result}, user_id) do
    DomainEventBus.dispatch(@context, MessagingEvents.user_data_anonymized(user_id))

    Logger.info("Anonymized messaging data for user",
      user_id: user_id,
      messages_anonymized: result.messages_anonymized,
      participants_updated: result.participants_updated
    )

    {:ok, result}
  end

  defp handle_result({:error, reason} = error, user_id) do
    Logger.error("Failed to anonymize messaging data for user",
      user_id: user_id,
      reason: inspect(reason)
    )

    error
  end
end
