defmodule KlassHero.Shared.ChangesetErrors do
  @moduledoc """
  Converts an `Ecto.Changeset`'s errors into a flat
  `[{field :: atom, message :: String.t()}]` list for anything that has to show a
  validation failure to a person. Expands `%{count}`-style placeholders so messages
  like `"should be at most %{count} character(s)"` don't leak to end users.

  Lives in Shared rather than a context because it knows only about Ecto: Enrollment's
  commands surface it to the LiveView layer, and Enrollment stores it as the context of
  a failed invite for the provider to read.

  Two shapes, for two moments:

  - `field_list/1` renders now — messages come back expanded, ready to show.
  - `to_payload/1` renders later — the msgid stays unexpanded so a reader in another
    locale can still look it up, and the values ride alongside as JSON-safe bindings.
    `interpolate/2` is the second half, applied after the translation (#1340).

  Formatting must never raise — this helper is called on the error path
  where throwing would swallow the real validation errors. Unknown
  placeholders fall through unchanged, as do placeholders whose opt is `nil`:
  a visible `%{gap}` says the validator forgot a value, where the empty string
  this used to render said nothing at all.
  """

  @doc """
  Flatten a changeset's errors into `[{field, expanded_message}]` pairs.
  """
  @spec field_list(Ecto.Changeset.t()) :: [{atom(), String.t()}]
  def field_list(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&expand/1)
    |> Enum.flat_map(fn {field, messages} ->
      Enum.map(messages, fn msg -> {field, msg} end)
    end)
  end

  @doc """
  Flatten a changeset's errors into JSON-safe `%{"field", "msg", "bindings"}` maps.

  For errors that are persisted and read back later. The message is the raw gettext
  msgid, still carrying its `%{...}` placeholders, because the reader translates before
  interpolating — expanding here would produce a string no catalog contains.
  """
  @spec to_payload(Ecto.Changeset.t()) :: [%{String.t() => term()}]
  def to_payload(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} -> {msg, normalize_bindings(opts)} end)
    |> Enum.flat_map(fn {field, errors} ->
      for {msg, bindings} <- errors do
        %{"field" => Atom.to_string(field), "msg" => msg, "bindings" => bindings}
      end
    end)
  end

  # Every placeholder the "errors" catalog interpolates — `mix gettext.extract` produces
  # no others, because these are the only ones Ecto's own validators emit. Closed and
  # literal on purpose: bindings come back from jsonb, and `String.to_existing_atom/1`
  # over stored data raises once an atom is deleted in a later release.
  @gettext_keys %{"count" => :count, "number" => :number}

  @doc """
  The subset of stored bindings Gettext can interpolate itself, atom-keyed.

  Gettext logs an error through `handle_missing_bindings/2` for every placeholder it
  cannot bind, so a translation call must be handed these rather than an empty map —
  otherwise a single failed invite logs on every render of the table it appears in.
  `interpolate/2` still runs afterwards and covers any key outside this set.
  """
  @spec gettext_bindings(%{String.t() => term()}) :: %{atom() => term()}
  def gettext_bindings(bindings) when is_map(bindings) do
    for {key, atom} <- @gettext_keys, {:ok, value} <- [Map.fetch(bindings, key)], into: %{} do
      {atom, value}
    end
  end

  @doc """
  Substitute `%{key}` placeholders from a string-keyed binding map.

  String-keyed on purpose: bindings come back from jsonb, and converting their keys to
  atoms would tie a render to atoms that may no longer exist.
  """
  @spec interpolate(String.t(), %{String.t() => term()}) :: String.t()
  def interpolate(msg, bindings) when is_binary(msg) and is_map(bindings) do
    Regex.replace(~r"%{(\w+)}", msg, fn match, key ->
      case Map.fetch(bindings, key) do
        {:ok, value} -> to_string(value)
        :error -> match
      end
    end)
  end

  defp expand({msg, opts}), do: interpolate(msg, normalize_bindings(opts))

  defp normalize_bindings(opts) do
    for {key, value} <- opts, {:ok, scalar} <- [normalize_value(value)], into: %{} do
      {Atom.to_string(key), scalar}
    end
  end

  defp normalize_value(value) when is_number(value) or is_binary(value) or is_boolean(value), do: {:ok, value}
  defp normalize_value(nil), do: :drop
  defp normalize_value(value) when is_atom(value), do: {:ok, Atom.to_string(value)}

  # A custom validator can put any term in opts. Anything with no string form is dropped
  # rather than left to raise on the render path.
  defp normalize_value(value) do
    {:ok, to_string(value)}
  rescue
    Protocol.UndefinedError -> :drop
  end
end
