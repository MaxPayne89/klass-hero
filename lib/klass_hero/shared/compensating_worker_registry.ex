defmodule KlassHero.Shared.CompensatingWorkerRegistry do
  @moduledoc """
  The one list of workers whose dead jobs get swept for compensation.

  Being in this list is the only condition, so a worker either gets its
  compensation reconciled after the job dies or is visibly absent from
  `config/config.exs` — the same bargain `EventConsumerRegistry` makes for event
  delivery.

  It is a list rather than a `function_exported?/3` scan for two reasons. The
  sweep needs a bounded `worker in ^names` filter, because a discarded job from a
  worker that never compensates would otherwise be re-examined on every tick for
  as long as the Pruner keeps its row. And discovering implementers means loading
  every module in the application, which starves the code server (#1232).
  """

  @doc "Workers registered for compensation sweeping."
  @spec workers() :: [module()]
  def workers do
    Application.get_env(:klass_hero, :compensating_workers, [])
  end

  @doc """
  Registered workers as `oban_jobs.worker` stores them.

  `Oban.Worker.to_string/1` rather than `Kernel.to_string/1`: the column holds
  `"KlassHero.Family..."`, not the `"Elixir."`-prefixed atom text, so a raw
  conversion would match nothing.
  """
  @spec worker_names() :: [String.t()]
  def worker_names do
    Enum.map(workers(), &Oban.Worker.to_string/1)
  end
end
