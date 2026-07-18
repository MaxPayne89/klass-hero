defmodule KlassHero.QueryCounter do
  @moduledoc """
  Test helper that counts Ecto queries executed during a block.

  Attaches a temporary `:telemetry` handler to the Repo's
  `[:klass_hero, :repo, :query]` event and tallies emissions into an atomic
  `:counters` reference. `:counters` is used (rather than message-passing to the
  test pid) so queries emitted from OTHER processes — e.g. a LiveView
  `start_async/3` task — are still counted, since the handler runs in whichever
  process executes the query.

  ## Usage

      {result, query_count} = QueryCounter.count(fn -> Context.some_read() end)
      assert query_count == 1

  Note: only synchronous work done inside `fun` is guaranteed to be counted.
  When measuring async work (e.g. `handle_async`), make sure the block waits for
  that work to complete (render/await) before returning.
  """

  @event [:klass_hero, :repo, :query]

  @doc """
  Runs `fun`, returning `{result, query_count}` where `query_count` is the number
  of Ecto queries executed during the call.
  """
  @spec count((-> result)) :: {result, non_neg_integer()} when result: term()
  def count(fun) when is_function(fun, 0) do
    counter = :counters.new(1, [:write_concurrency])
    handler_id = {__MODULE__, System.unique_integer([:positive])}

    :telemetry.attach(
      handler_id,
      @event,
      fn _event, _measurements, _metadata, _config -> :counters.add(counter, 1, 1) end,
      nil
    )

    try do
      result = fun.()
      {result, :counters.get(counter, 1)}
    after
      :telemetry.detach(handler_id)
    end
  end

  @doc "Convenience wrapper returning only the query count, discarding the result."
  @spec count_only((-> term())) :: non_neg_integer()
  def count_only(fun) when is_function(fun, 0) do
    {_result, count} = count(fun)
    count
  end

  @doc """
  Runs `fun`, returning `{result, total_rows}` where `total_rows` is the sum of
  `num_rows` across every query executed during the call.

  Useful for proving a query is bounded in SQL (e.g. `LIMIT`) rather than trimmed
  in Elixir after fetching everything — the return value can be identical either
  way, but the rows pulled from the database differ.
  """
  @spec count_rows((-> result)) :: {result, non_neg_integer()} when result: term()
  def count_rows(fun) when is_function(fun, 0) do
    counter = :counters.new(1, [:write_concurrency])
    handler_id = {__MODULE__, :rows, System.unique_integer([:positive])}

    :telemetry.attach(
      handler_id,
      @event,
      fn _event, _measurements, metadata, _config ->
        case metadata do
          %{result: {:ok, %{num_rows: n}}} when is_integer(n) -> :counters.add(counter, 1, n)
          _ -> :ok
        end
      end,
      nil
    )

    try do
      result = fun.()
      {result, :counters.get(counter, 1)}
    after
      :telemetry.detach(handler_id)
    end
  end
end
