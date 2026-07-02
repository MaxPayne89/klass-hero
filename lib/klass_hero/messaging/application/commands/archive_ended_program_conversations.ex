defmodule KlassHero.Messaging.Application.Commands.ArchiveEndedProgramConversations do
  @moduledoc """
  Use case for archiving conversations associated with programs that have ended.

  This use case:
  1. Calculates the cutoff date based on configuration
  2. Archives all program_broadcast conversations for programs that ended before the cutoff
  3. Publishes a bulk archived event for consistency

  Typically run by a background worker (Oban) on a daily schedule.
  """

  alias KlassHero.Messaging.Domain.Events.MessagingEvents
  alias KlassHero.Shared.DomainEventBus

  require Logger

  @context KlassHero.Messaging
  @retention_config Application.compile_env!(:klass_hero, [:messaging, :retention])

  @default_days_after_program_end 30
  @default_retention_period_days 30

  @doc """
  Archives conversations for programs that ended before the configured cutoff.

  ## Parameters
  - opts: Optional parameters
    - days_after_program_end: Number of days after program end to archive (default: #{@default_days_after_program_end})
    - retention_period_days: Number of days to retain archived conversations (default: #{@default_retention_period_days})

  ## Returns
  - `{:ok, %{count: n, conversation_ids: [ids]}}` - Success with count and IDs
  - `{:error, reason}` - Failure
  """
  @spec execute(keyword()) :: {:ok, %{count: non_neg_integer(), conversation_ids: [String.t()]}}
  def execute(opts \\ []) do
    days = Keyword.get_lazy(opts, :days_after_program_end, &default_days_after_program_end/0)

    retention_days =
      Keyword.get_lazy(opts, :retention_period_days, &default_retention_period_days/0)

    cutoff_date =
      Date.utc_today()
      |> Date.add(-days)
      |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    Logger.info("Archiving conversations for programs ended before cutoff",
      cutoff_date: cutoff_date,
      days_after_program_end: days,
      retention_period_days: retention_days
    )

    case KlassHero.Messaging.archive_ended_program_conversations(
           cutoff_date,
           retention_days
         ) do
      {:ok, %{count: 0} = result} ->
        Logger.debug("No conversations to archive for ended programs")
        {:ok, result}

      {:ok, %{count: count, conversation_ids: ids} = result} ->
        publish_event(ids, count)

        Logger.info("Archived conversations for ended programs",
          count: count,
          cutoff_date: cutoff_date
        )

        {:ok, result}
    end
  end

  defp publish_event(conversation_ids, count) do
    event = MessagingEvents.conversations_archived(conversation_ids, :program_ended, count)
    DomainEventBus.dispatch(@context, event)
    :ok
  end

  defp default_days_after_program_end do
    @retention_config[:days_after_program_end] || @default_days_after_program_end
  end

  defp default_retention_period_days do
    @retention_config[:retention_period_days] || @default_retention_period_days
  end
end
