defmodule KlassHero.Shared.Projection.WithBootstrapRetry do
  @moduledoc """
  Opt-in mixin for `KlassHero.Shared.Projection`. Wraps `apply_bootstrap/1`
  in a `try/rescue` with linear backoff so transient infrastructure failures
  do not immediately crash the projection.

  ## Options

  - `:max_attempts` — defaults to `3`. After exhausting attempts the original
    exception is reraised so the supervisor sees it.
  - `:base_delay_ms` — defaults to `5_000`. Linear backoff: `base_delay_ms * retry_count`.

  Use immediately after `use KlassHero.Shared.Projection, ...`.
  """

  defmacro __using__(opts) do
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    base_delay_ms = Keyword.get(opts, :base_delay_ms, 5_000)

    quote bind_quoted: [max_attempts: max_attempts, base_delay_ms: base_delay_ms] do
      @projection_max_attempts max_attempts
      @projection_base_delay_ms base_delay_ms

      defp apply_bootstrap(state) do
        count = bootstrap_impl()
        Logger.info("#{inspect(__MODULE__)} projection started", count: count)
        {:noreply, %{state | bootstrapped: true, retry_count: 0}}
      rescue
        error ->
          retry_count = Map.get(state, :retry_count, 0) + 1

          if retry_count > @projection_max_attempts do
            reraise error, __STACKTRACE__
          else
            Logger.error("#{inspect(__MODULE__)}: bootstrap failed, scheduling retry",
              error: Exception.message(error),
              retry_count: retry_count
            )

            Process.send_after(self(), :retry_bootstrap, @projection_base_delay_ms * retry_count)
            {:noreply, Map.put(state, :retry_count, retry_count)}
          end
      end

      defoverridable apply_bootstrap: 1
    end
  end
end
