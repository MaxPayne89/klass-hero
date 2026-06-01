defmodule KlassHero.Shared.RateLimitedEmailWorker do
  @moduledoc """
  Macro for Oban workers that send email through Resend (or any 429-returning
  upstream). Wraps `KlassHero.Shared.Tracing.TracedWorker` and adds a `backoff/1`
  override that backs off harder on rate-limit errors.

  ## Usage

      defmodule MyApp.Workers.SomeEmailWorker do
        use KlassHero.Shared.RateLimitedEmailWorker, queue: :email, max_attempts: 3

        @impl KlassHero.Shared.Tracing.TracedWorker
        def execute(%Oban.Job{} = job), do: ...
      end

  Backoff schedule:
  - Rate-limit error (`%{reason: {429, _}}` or `%{reason: :rate_limited}`):
    30s → 60s → 120s → … capped at 300s
  - Other errors: 10s → 20s → 40s → … capped at 120s
  """

  @doc "Returns true when the captured Oban error reason signals a rate limit."
  @spec rate_limit_error?(term()) :: boolean()
  def rate_limit_error?(%{reason: {429, _}}), do: true
  def rate_limit_error?(%{reason: :rate_limited}), do: true
  def rate_limit_error?(_), do: false

  @doc """
  Rate-limit-aware Oban backoff: longer waits when the captured error is a rate
  limit, the standard exponential schedule otherwise.
  """
  @spec backoff(Oban.Job.t()) :: pos_integer()
  def backoff(%Oban.Job{attempt: attempt, unsaved_error: unsaved_error}) do
    if rate_limit_error?(unsaved_error) do
      trunc(min(30 * :math.pow(2, attempt - 1), 300))
    else
      trunc(min(10 * :math.pow(2, attempt - 1), 120))
    end
  end

  @doc false
  defmacro __using__(opts) do
    quote do
      use KlassHero.Shared.Tracing.TracedWorker, unquote(opts)

      alias KlassHero.Shared.RateLimitedEmailWorker

      @impl Oban.Worker
      def backoff(%Oban.Job{} = job), do: RateLimitedEmailWorker.backoff(job)

      defoverridable backoff: 1
    end
  end
end
