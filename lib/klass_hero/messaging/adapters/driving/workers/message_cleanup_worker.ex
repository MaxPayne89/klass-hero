defmodule KlassHero.Messaging.Adapters.Driving.Workers.MessageCleanupWorker do
  @moduledoc """
  Oban worker that archives conversations for programs that ended.

  This is a thin wrapper around the ArchiveEndedProgramConversations use case,
  scheduled to run daily at 3 AM via Oban cron configuration.

  The number of days after program end before archiving can be overridden
  via job args for testing purposes.
  """

  use Oban.Worker, queue: :cleanup, max_attempts: 3

  alias KlassHero.Messaging.ArchiveEndedProgramConversations

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    opts = build_opts_from_args(args)

    Logger.info("Starting message cleanup worker", opts: opts)

    {:ok, %{count: count}} = ArchiveEndedProgramConversations.execute(opts)
    Logger.info("Message cleanup worker completed", archived_count: count)
    :ok
  end

  defp build_opts_from_args(args) when is_map(args) do
    args
    |> Map.take(["days_after_program_end"])
    |> Enum.map(fn
      {"days_after_program_end", value} when is_integer(value) -> {:days_after_program_end, value}
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp build_opts_from_args(_), do: []
end
