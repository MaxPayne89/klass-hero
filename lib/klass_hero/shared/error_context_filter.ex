defmodule KlassHero.Shared.ErrorContextFilter do
  @moduledoc """
  Narrows the context ErrorTracker persists, before it is written.

  `ErrorTracker.Integrations.Oban` sets the whole of `job.args` as context on every
  job start, and ErrorTracker stores context alongside each error occurrence in the
  production database. `ProcessInviteClaimWorker`'s args carry a child's name, date of
  birth and medical conditions, so the unfiltered default would put children's health
  data in an error log.

  Job args are therefore allowlisted rather than denylisted: a new worker, or a new
  field on an existing one, is excluded until someone adds it here. Everything else in
  the context passes through — `KlassHeroWeb.Router.set_error_tracker_context/2`'s
  user_id/email predate this filter and are deliberate.

  Wired via `config :error_tracker, filter: KlassHero.Shared.ErrorContextFilter`.
  """

  @behaviour ErrorTracker.Filter

  @args_key "job.args"
  @redacted_key "job.args.redacted"

  # Correlation ids only — enough to find the row this job was about, never its contents.
  # "trace_context" carries OTel propagation (`Shared.Tracing.Context.inject_into_args/1`);
  # dropping it would silently unlink every error report from its Honeycomb trace.
  @allowed_args ~w(
    invite_id user_id program_id parent_id child_id provider_id
    enrollment_id staff_member_id conversation_id message_id email_id
    trace_context
  )

  @impl true
  def sanitize(context) when is_map(context) do
    case context do
      %{@args_key => args} when is_map(args) -> put_filtered_args(context, args)
      _ -> context
    end
  end

  defp put_filtered_args(context, args) do
    kept = Map.take(args, @allowed_args)
    context = Map.put(context, @args_key, kept)

    case Map.keys(args) -- Map.keys(kept) do
      [] -> context
      dropped -> Map.put(context, @redacted_key, Enum.sort(dropped))
    end
  end
end
