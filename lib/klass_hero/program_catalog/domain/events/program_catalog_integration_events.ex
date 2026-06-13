defmodule KlassHero.ProgramCatalog.Domain.Events.ProgramCatalogIntegrationEvents do
  @moduledoc """
  Factory for ProgramCatalog integration events (public cross-context contract).

  - `:program_created` — new program created; downstream contexts may react
  - `:program_updated` — program fields changed; downstream read models should refresh
  """

  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  @typedoc "Payload for `:program_created` events."
  @type program_created_payload :: %{
          required(:program_id) => String.t(),
          optional(atom()) => term()
        }

  @typedoc "Payload for `:program_updated` events."
  @type program_updated_payload :: %{
          required(:program_id) => String.t(),
          optional(atom()) => term()
        }

  @source_context :program_catalog
  @entity_type :program

  def program_created(program_id, payload \\ %{}, opts \\ [])

  def program_created(program_id, payload, opts) when is_binary(program_id) and byte_size(program_id) > 0 do
    base_payload = %{program_id: program_id}

    IntegrationEvent.new(
      :program_created,
      @source_context,
      @entity_type,
      program_id,
      # Map.merge order ensures base_payload's :program_id wins over any caller-supplied value.
      Map.merge(payload, base_payload),
      opts
    )
  end

  def program_created(program_id, _payload, _opts) do
    raise ArgumentError,
          "program_created/3 requires a non-empty program_id string, got: #{inspect(program_id)}"
  end

  def program_updated(program_id, payload \\ %{}, opts \\ [])

  def program_updated(program_id, payload, opts) when is_binary(program_id) and byte_size(program_id) > 0 do
    base_payload = %{program_id: program_id}

    IntegrationEvent.new(
      :program_updated,
      @source_context,
      @entity_type,
      program_id,
      # Map.merge order ensures base_payload's :program_id wins over any caller-supplied value.
      Map.merge(payload, base_payload),
      opts
    )
  end

  def program_updated(program_id, _payload, _opts) do
    raise ArgumentError,
          "program_updated/3 requires a non-empty program_id string, got: #{inspect(program_id)}"
  end
end
