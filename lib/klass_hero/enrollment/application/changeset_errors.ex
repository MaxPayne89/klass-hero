defmodule KlassHero.Enrollment.Application.ChangesetErrors do
  @moduledoc """
  Converts an `Ecto.Changeset`'s errors into the flat
  `[{field :: atom, message :: String.t()}]` list that enrollment commands
  surface to the LiveView layer. Expands `%{count}`-style placeholders so
  messages like `"should be at most %{count} character(s)"` don't leak to
  end users.

  Formatting must never raise — this helper is called on the error path
  where throwing would swallow the real validation errors. Unknown
  placeholders fall through unchanged.
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

  defp expand({msg, opts}) do
    Regex.replace(~r"%{(\w+)}", msg, fn match, key -> lookup(opts, key, match) end)
  end

  # Catches only ArgumentError from String.to_existing_atom/1 — other failures surface.
  defp lookup(opts, key, default) do
    atom = String.to_existing_atom(key)

    case Keyword.fetch(opts, atom) do
      {:ok, value} -> to_string(value)
      :error -> default
    end
  rescue
    ArgumentError -> default
  end
end
