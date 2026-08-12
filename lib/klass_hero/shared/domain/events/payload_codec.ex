defmodule KlassHero.Shared.Domain.Events.PayloadCodec do
  @moduledoc """
  What an event payload leaf may be, and how it crosses `jsonb`.

  `jsonb` has strings, numbers, booleans and null. Everything else a producer puts
  in a payload either has to be written down as one of those and rebuilt on the way
  back, or rejected before the event is built.

  Two callers ask, at two different moments:

  - `EventMetadata.validate_payload!/1` asks `encodable?/1` at `Event.new/6`, so an
    unencodable value fails where a developer caused it rather than in a worker.
  - `CriticalEventSerializer` calls `encode/1` on the way out and `decode/2` on the
    way back, walking the payload and mirroring the tags into a `payload_types`
    sidecar beside it.

  ## Why the list lives here and not in either caller

  It lived in both. `EventMetadata` knew which types were *legal* and the serializer
  knew how each one *crossed*, and the two had to agree by hand — #1316 (typed value
  support) and #1317 (atoms) each had to edit both halves in lockstep, and the gap
  between them is exactly where #1311's two production bugs sat. Adding a type is now
  one edit in one module.

  Only leaves live here. The walks stay with their callers because they do different
  jobs: the guard's walk tracks a path so its error can say *where*, and the
  serializer's builds a shape-mirrored sidecar.

  ## Two traps

  - **`nil`, `true` and `false` are atoms.** Their clauses come first, so they stay
    JSON `null`/`true`/`false` rather than becoming the strings `"nil"`/`"true"`.
    Tagging them would change what every `Map.get(payload, :key) || default` in a
    consumer returns.
  - **`decode/2` needs the atom to already exist.** `String.to_existing_atom/1` is
    the same bet the payload-key and `event_type` atomization already make: the atom
    is domain-defined, so the module defining it is loaded by the time an event
    carrying it is delivered.

  ## An unknown tag means "leave it alone", and so does a missing one

  Args staged before a tag existed carry none, so `decode/2` returns the value as
  `jsonb` left it — what in-flight Oban jobs and `undelivered_events` rows need at
  deploy.

  A tag this version does not recognise degrades the same way, which is what makes a
  rollback safe in the other direction. That is not free: the serializer before #1317
  had a decode clause per known tag and no fallback, so a job carrying a tag it had
  never heard of raised `FunctionClauseError` rather than degrading. Rolling *back*
  past this commit still has that window, because the old code is what lacks the
  fallback; rolling back to any version from here on does not.
  """

  @typedoc "A value `jsonb` stores natively."
  @type json :: String.t() | number() | boolean() | nil

  @typedoc "Records what a value was, or `nil` when it was already a JSON scalar."
  @type tag :: String.t() | nil

  @doc """
  Whether this leaf can cross `jsonb` and come back as itself.
  """
  @spec encodable?(term()) :: boolean()
  def encodable?(value) when is_binary(value) when is_number(value), do: true
  def encodable?(value) when is_atom(value), do: true
  def encodable?(%Date{}), do: true
  def encodable?(%Time{}), do: true
  def encodable?(%DateTime{}), do: true
  def encodable?(%NaiveDateTime{}), do: true
  def encodable?(%Decimal{}), do: true
  def encodable?(_value), do: false

  @doc """
  Encodes a leaf into a JSON scalar and the tag that restores it.

  Raises `ArgumentError` on a value nothing can record — a tuple, a PID, a schema
  struct. `Event.new/6` rejects those too, so reaching this raise means the event
  was built some other way.
  """
  @spec encode(term()) :: {json(), tag()}
  # Ahead of the is_atom/1 clause on purpose: all three are atoms, and jsonb stores
  # them natively.
  def encode(nil), do: {nil, nil}
  def encode(value) when is_boolean(value), do: {value, nil}
  def encode(value) when is_binary(value) when is_number(value), do: {value, nil}
  def encode(value) when is_atom(value), do: {Atom.to_string(value), "atom"}
  def encode(%Date{} = value), do: {Date.to_iso8601(value), "date"}
  def encode(%Time{} = value), do: {Time.to_iso8601(value), "time"}
  def encode(%DateTime{} = value), do: {DateTime.to_iso8601(value), "datetime"}
  def encode(%NaiveDateTime{} = value), do: {NaiveDateTime.to_iso8601(value), "naive_datetime"}
  def encode(%Decimal{} = value), do: {Decimal.to_string(value), "decimal"}

  def encode(value) do
    raise ArgumentError,
          "Event payload value #{inspect(value)} cannot cross the Oban jsonb boundary. " <>
            "A payload may carry strings, numbers, booleans, nil, atoms, and " <>
            "Date/Time/DateTime/NaiveDateTime/Decimal structs (nested in maps and lists); " <>
            "encode anything else as a JSON scalar in the producer. Event.new/6 rejects " <>
            "this too, so reaching here means the event was built some other way."
  end

  @doc """
  Rebuilds what `encode/1` wrote down. An untagged value passes through unchanged.
  """
  @spec decode(json(), tag()) :: term()
  def decode(value, nil), do: value
  def decode(value, "atom"), do: String.to_existing_atom(value)
  def decode(value, "date"), do: Date.from_iso8601!(value)
  def decode(value, "time"), do: Time.from_iso8601!(value)
  def decode(value, "naive_datetime"), do: NaiveDateTime.from_iso8601!(value)
  def decode(value, "decimal"), do: Decimal.new(value)

  # DateTime.from_iso8601/1 returns the instant plus a separate offset, and only the
  # instant is kept — so a DateTime comes back in UTC. Every producer builds UTC, so
  # nothing observes the difference.
  def decode(value, "datetime") do
    {:ok, datetime, _utc_offset} = DateTime.from_iso8601(value)
    datetime
  end

  # A tag this version does not know was written by a newer one. Degrade to the raw
  # scalar — the same thing an untagged value gets — rather than raising.
  #
  # Without this clause a rollback dead-letters every job the newer version staged,
  # which is what the serializer before #1317 would do: its `revive/2` had a clause
  # per known tag and no fallback, so a job carrying `"atom"` raised FunctionClauseError
  # on any instance still running the old code. On a rolling deploy both versions read
  # the same queue, so that window is real rather than theoretical.
  def decode(value, _unrecognised_tag), do: value
end
