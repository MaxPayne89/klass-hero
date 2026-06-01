defmodule KlassHero.Shared.Domain.Validation do
  @moduledoc """
  Accumulator-style validators shared across domain model `validate/1` pipelines.

  Each function takes an error-list accumulator, a field name, and a value, and
  returns the accumulator — prepending a message when the value is invalid. This
  lets models compose checks with a simple `|>` pipeline.
  """

  @type errors :: [String.t()]

  @doc """
  Requires `value` to be a non-empty (after trimming) string.

  Prepends `"<field> must be a string"` for non-binaries and
  `"<field> cannot be empty"` for blank strings.
  """
  @spec validate_required_string(errors(), atom() | String.t(), term()) :: errors()
  def validate_required_string(errors, field, value) when is_binary(value) do
    if String.trim(value) == "" do
      ["#{field} cannot be empty" | errors]
    else
      errors
    end
  end

  def validate_required_string(errors, field, _value) do
    ["#{field} must be a string" | errors]
  end
end
