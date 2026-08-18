defmodule KlassHero.Shared.ErrorReasonFilter do
  @moduledoc """
  Narrows the exception message ErrorTracker persists as `reason`.

  Sibling of `KlassHero.Shared.ErrorContextFilter`, which cannot reach this surface:
  `ErrorTracker.report/3` runs the configured filter over the *context* only, then passes
  `reason` — `Exception.message(exception)` — straight to storage. Any exception that
  interpolates the value that caused it therefore writes that value to
  `error_tracker_errors.reason` and `error_tracker_occurrences.reason` (#1398).

  Applied at the write boundary by `KlassHero.Shared.ErrorStoreRepo`, so every report path
  is covered — Phoenix, Oban, a manual `ErrorTracker.report/3`, and any integration a future
  `error_tracker` adds.

  Narrowing happens in two stages, because exceptions leak in two different shapes:

    * **After a line break.** Elixir renders a payload-bearing exception as a safe clause, a
      blank line, then the interpolated term (`key :x not found in:\\n\\n    %{...}`);
      Postgres puts the offending value in the `detail` that follows the same break. The
      first line is kept and a `[redacted]` marker announces what went — the marker is the
      point, exactly as the sibling filter keeps param keys in place.

    * **Inline.** `Oban.PerformError` (`<worker> failed with <term>`), `ArgumentError`, and
      any custom exception interpolating into its own `:message` put the payload on the same
      line as the clause. Nothing structural separates the two, so the first line is judged
      against `@safe_shapes`.

  **Closed by default.** A first line matching no known shape is replaced wholesale, so a new
  exception kind is minimised until someone adds it here. The cost is real: the first
  occurrence of a novel exception shows the marker instead of its message, and triage falls
  back to `kind`, `source_function`, `source_line` and the stacktrace. Every kind seen in
  production is covered below, so this bites on novel custom exceptions only.
  """

  @redaction_marker "[redacted]"
  @unrecognised_marker "[reason redacted: unrecognised message shape]"

  # First lines proven to carry no interpolated value, each named by the exception it covers.
  @safe_shapes [
    # KeyError, with and without a term
    ~r/^key .+ not found(?: in:)?$/,
    # MatchError
    ~r/^no match of right hand side value:$/,
    # CaseClauseError
    ~r/^no case clause matching:$/,
    # FunctionClauseError
    ~r{^no function clause matching in .+/\d+$},
    # WithClauseError
    ~r/^no with clause matching:$/,
    # Protocol.UndefinedError
    ~r/^protocol .+ not implemented for .+$/,
    # Postgrex.Error — the value lives in `detail`, below the break
    ~r/^ERROR \d{5} \(\w+\) /,
    # Ecto.ConstraintError
    ~r/^constraint error when attempting to \w+ struct:$/,
    # Ecto.NoResultsError / Ecto.MultipleResultsError
    ~r/^expected at (?:least|most) one result but got /,
    # Oban.TimeoutError
    ~r/^.+ timed out after \d+ms$/,
    # DBConnection timeouts and checkout failures
    ~r/^(?:client .+ timed out|connection not available)/
  ]

  # The head identifies the error, the tail is the payload — Oban.PerformError wraps whatever
  # term a worker returned in `{:error, term}`, so the tail is arbitrary user data.
  @inline_payload_shape ~r/^(?<head>.+? failed with ).+$/s

  @spec sanitize(String.t()) :: String.t()
  def sanitize(reason) when is_binary(reason) do
    {head, dropped?} = split_first_line(reason)

    if safe_shape?(head), do: mark(head, dropped?), else: redact(head)
  end

  defp split_first_line(reason) do
    case String.split(reason, "\n", parts: 2) do
      [head] -> {head, false}
      [head, ""] -> {head, false}
      [head, _payload] -> {head, true}
    end
  end

  defp safe_shape?(head), do: Enum.any?(@safe_shapes, &Regex.match?(&1, head))

  defp mark(head, false), do: head
  defp mark(head, true), do: head <> " " <> @redaction_marker

  defp redact(head) do
    case Regex.run(@inline_payload_shape, head, capture: ["head"]) do
      [prefix] -> prefix <> @redaction_marker
      nil -> @unrecognised_marker
    end
  end
end
