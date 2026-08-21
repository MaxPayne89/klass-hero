defmodule KlassHero.Shared.ErrorContextFilter do
  @moduledoc """
  Narrows the context ErrorTracker persists, before it is written.

  ErrorTracker stores context alongside each error occurrence in the production
  database, and two of the things it captures carry user-submitted data verbatim:
  Oban job args, and the params of the request or LiveView event that crashed.
  `ProcessInviteClaimWorker`'s args and the children form both carry a child's name,
  date of birth and medical conditions, so the unfiltered default would put children's
  health data in an error log.

  Both are therefore closed by default — a new worker, a new form, or a new field on an
  existing one is minimised until someone allowlists it. The two halves narrow
  differently because they fail differently:

    * **Job args** are *removed*, and the dropped names recorded in a sibling
      `job.args.redacted` key. Without that sibling an operator would read the surviving
      args as the whole story.

    * **Params** keep their keys and lose their values — a nested form map becomes a
      marker naming its fields, an unlisted scalar becomes `"[redacted]"`. The key
      staying in place is what announces the redaction, so no sibling key is needed.
      Which fields were submitted is the debugging signal; what was in them is the PII.

  Everything else in the context passes through — `KlassHeroWeb.Router.set_error_tracker_context/2`'s
  user_id/email predate this filter and are deliberate.

  On the report path `sanitize/1` is called once, on the fully merged context, so a single
  LiveView crash can arrive carrying mount, `handle_params` and `handle_event` params at
  once. Each key is narrowed independently.

  ## Idempotence

  `sanitize/1` is a fixpoint: narrowing an already-narrowed context returns it unchanged. The
  report path never needed that, but a backfill does — #1406 narrows the rows written before
  this filter existed, and cannot avoid meeting rows it has already narrowed. Without the
  property, a second pass would read a params marker as an unlisted *string* and collapse
  `"[8 keys redacted: allergies, …]"` to `"[redacted]"`, destroying the field names that are the
  entire point of the params half.

  The args half is a fixpoint for free — `Map.take/2` of an already-taken map keeps everything,
  so nothing is dropped and no sibling key is rewritten. The params half needs `already_narrowed?/1`,
  which recognises a marker by its exact shape. The cost is that a value the user typed which
  matches that shape survives verbatim; `@nested_marker` is anchored end to end to keep that
  surface as small as it can be without changing what a marker *is*.

  Wired via `config :error_tracker, filter: KlassHero.Shared.ErrorContextFilter`.

  ## What this filter does NOT cover

  `reason` — the exception message — is out of reach here, and no configuration can change
  that: `ErrorTracker.report/3` runs this filter over the context, then passes `reason` to
  storage separately, and `ErrorTracker.Filter` has no second callback. An exception that
  interpolates the value that caused it (`MatchError`, `KeyError`, `Oban.PerformError`)
  therefore leaks through a surface this module cannot see (#1398). Narrowing it happens at
  the write boundary instead — see `KlassHero.Shared.ErrorReasonFilter` and
  `KlassHero.Shared.ErrorStoreRepo`.
  """

  @behaviour ErrorTracker.Filter

  @args_key "job.args"
  @redacted_key "job.args.redacted"

  # Every key under which ErrorTracker records user-submitted params.
  # `request.params` is the controller/plug side; there is no "phoenix.params".
  @param_keys ~w(live_view.event_params live_view.params request.params)

  @scalar_marker "[redacted]"

  # Exactly what nested_marker/1 emits, anchored end to end. Recognising a marker by its shape
  # is what makes sanitize/1 idempotent, and the anchoring is what keeps that cheap: a value
  # the user typed passes through only if it matches this whole string, which no name, date or
  # medical note does.
  @nested_marker ~r/^\[\d+ keys redacted: [^\[\]]*\]$/

  # Correlation ids only — enough to find the row this job was about, never its contents.
  # "trace_context" carries OTel propagation (`Shared.Tracing.Context.inject_into_args/1`);
  # dropping it would silently unlink every error report from its Honeycomb trace.
  @allowed_args ~w(
    invite_id user_id program_id parent_id child_id provider_id
    enrollment_id staff_member_id conversation_id message_id email_id
    trace_context
  )

  # Correlation ids, the flags and navigation state that explain what the user was doing,
  # and "_target" — LiveView's name of the field that triggered the change, which is a
  # field name, not a field value. "consent" earns its place by precedent: in #1322 the
  # captured flag was the only surviving proof that a guardian had ticked the box.
  @allowed_params ~w(
    invite_id user_id program_id parent_id child_id provider_id
    enrollment_id staff_member_id conversation_id message_id email_id
    id consent page per_page sort filter tab _target
  )

  @impl true
  def sanitize(context) when is_map(context) do
    context
    |> filter_args()
    |> filter_params()
  end

  defp filter_args(context) do
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

  defp filter_params(context) do
    Enum.reduce(@param_keys, context, fn key, acc ->
      case acc do
        %{^key => params} when is_map(params) and map_size(params) > 0 ->
          Map.put(acc, key, Map.new(params, &narrow_param/1))

        _ ->
          acc
      end
    end)
  end

  defp narrow_param({key, value}) do
    cond do
      to_string(key) in @allowed_params -> {key, value}
      already_narrowed?(value) -> {key, value}
      is_map(value) -> {key, nested_marker(value)}
      true -> {key, @scalar_marker}
    end
  end

  defp already_narrowed?(value) when is_binary(value) do
    value == @scalar_marker or Regex.match?(@nested_marker, value)
  end

  defp already_narrowed?(_value), do: false

  defp nested_marker(map) do
    names = map |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()

    "[#{length(names)} keys redacted: #{Enum.join(names, ", ")}]"
  end
end
