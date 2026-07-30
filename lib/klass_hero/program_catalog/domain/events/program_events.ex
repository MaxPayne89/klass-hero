defmodule KlassHero.ProgramCatalog.Domain.Events.ProgramEvents do
  @moduledoc """
  Factory module for creating Program events.

  ## Events

  - `:program_created` - Emitted when a provider creates a new program
  - `:program_updated` - Emitted when any program fields are updated, including
    scheduling changes (its payload carries the meeting/date fields)
  """

  alias KlassHero.Shared.Domain.Events.Event

  @source_context :program_catalog
  @entity_type :program

  def program_created(program_id, payload \\ %{}, opts \\ [])

  def program_created(program_id, payload, opts) when is_binary(program_id) and byte_size(program_id) > 0 do
    build(:program_created, program_id, payload, opts)
  end

  def program_created(program_id, _payload, _opts) do
    raise ArgumentError,
          "program_created/3 requires a non-empty program_id string, got: #{inspect(program_id)}"
  end

  def program_updated(program_id, payload \\ %{}, opts \\ [])

  def program_updated(program_id, payload, opts) when is_binary(program_id) and byte_size(program_id) > 0 do
    build(:program_updated, program_id, payload, opts)
  end

  def program_updated(program_id, _payload, _opts) do
    raise ArgumentError,
          "program_updated/3 requires a non-empty program_id string, got: #{inspect(program_id)}"
  end

  defp build(event_type, program_id, payload, opts) do
    Event.new(
      event_type,
      @source_context,
      @entity_type,
      program_id,
      # Overwrites rather than merges: the id argument wins over any caller-supplied :program_id.
      Map.put(payload, :program_id, program_id),
      opts
    )
  end
end
