defmodule KlassHero.Participation.Adapters.Driven.Persistence.Mappers.ParticipationRecordMapper do
  @moduledoc """
  Maps between ParticipationRecord domain model and ParticipationRecordSchema.

  This mapper ensures clean separation between the domain layer and persistence layer.
  """

  alias KlassHero.Participation.Adapters.Driven.Persistence.Schemas.ParticipationRecordSchema
  alias KlassHero.Participation.Domain.Models.ParticipationRecord
  alias KlassHero.Shared.Adapters.Driven.Persistence.MapperHelpers

  @doc "Converts a ParticipationRecordSchema to a ParticipationRecord domain model."
  @spec to_domain(ParticipationRecordSchema.t()) :: ParticipationRecord.t()
  def to_domain(%ParticipationRecordSchema{} = schema) do
    attrs = %{
      id: schema.id,
      session_id: schema.session_id,
      child_id: schema.child_id,
      parent_id: schema.parent_id,
      provider_id: schema.provider_id,
      status: schema.status,
      check_in_at: schema.check_in_at,
      check_in_notes: schema.check_in_notes,
      check_in_by: schema.check_in_by,
      check_out_at: schema.check_out_at,
      check_out_notes: schema.check_out_notes,
      check_out_by: schema.check_out_by,
      inserted_at: schema.inserted_at,
      updated_at: schema.updated_at,
      lock_version: schema.lock_version
    }

    MapperHelpers.from_persistence!(ParticipationRecord, attrs, schema.id)
  end

  @doc "Converts a ParticipationRecord domain model to attributes for persistence."
  @spec to_persistence(ParticipationRecord.t()) :: map()
  def to_persistence(%ParticipationRecord{} = record) do
    %{
      id: record.id,
      session_id: record.session_id,
      child_id: record.child_id,
      parent_id: record.parent_id,
      provider_id: record.provider_id,
      status: record.status,
      check_in_at: record.check_in_at,
      check_in_notes: record.check_in_notes,
      check_in_by: record.check_in_by,
      check_out_at: record.check_out_at,
      check_out_notes: record.check_out_notes,
      check_out_by: record.check_out_by,
      lock_version: record.lock_version
    }
  end

  @doc "Updates a schema struct with domain model values for update operations."
  @spec update_schema(ParticipationRecordSchema.t(), ParticipationRecord.t()) :: map()
  def update_schema(%ParticipationRecordSchema{}, %ParticipationRecord{} = record) do
    %{
      status: record.status,
      check_in_at: record.check_in_at,
      check_in_notes: record.check_in_notes,
      check_in_by: record.check_in_by,
      check_out_at: record.check_out_at,
      check_out_notes: record.check_out_notes,
      check_out_by: record.check_out_by,
      lock_version: record.lock_version
    }
  end
end
