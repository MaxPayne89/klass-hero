defmodule KlassHero.Shared.CommandResult do
  @moduledoc """
  Result-normalising helpers shared across application command use cases.
  """

  @doc """
  Wraps a domain validation failure (an `{:error, list}` of messages) into the
  canonical `{:error, {:validation_error, errors}}` tuple. Any other result —
  `{:ok, _}`, `{:error, changeset}`, `{:error, atom}` — passes through unchanged.

  Intended as the catch-all `else` of a command's `with` pipeline:

      with {:ok, _} <- Model.new(attrs),
           {:ok, persisted} <- repo.create(attrs) do
        {:ok, persisted}
      else
        result -> CommandResult.wrap_validation_errors(result)
      end
  """
  @spec wrap_validation_errors(term()) :: term()
  def wrap_validation_errors({:error, errors}) when is_list(errors) do
    {:error, {:validation_error, errors}}
  end

  def wrap_validation_errors(result), do: result
end
