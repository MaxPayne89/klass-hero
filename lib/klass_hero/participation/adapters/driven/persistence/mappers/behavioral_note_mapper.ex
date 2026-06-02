defmodule KlassHero.Participation.Adapters.Driven.Persistence.Mappers.BehavioralNoteMapper do
  @moduledoc """
  Maps between BehavioralNote domain model and BehavioralNoteSchema.

  This mapper ensures clean separation between the domain layer and persistence layer.
  """

  alias KlassHero.Participation.Adapters.Driven.Persistence.Schemas.BehavioralNoteSchema
  alias KlassHero.Participation.Domain.Models.BehavioralNote
  alias KlassHero.Shared.Adapters.Driven.Persistence.MapperHelpers

  @doc "Converts a BehavioralNoteSchema to a BehavioralNote domain model."
  @spec to_domain(BehavioralNoteSchema.t()) :: BehavioralNote.t()
  def to_domain(%BehavioralNoteSchema{} = schema) do
    attrs = %{
      id: schema.id,
      participation_record_id: schema.participation_record_id,
      child_id: schema.child_id,
      parent_id: schema.parent_id,
      provider_id: schema.provider_id,
      content: schema.content,
      status: schema.status,
      rejection_reason: schema.rejection_reason,
      submitted_at: schema.submitted_at,
      reviewed_at: schema.reviewed_at,
      inserted_at: schema.inserted_at,
      updated_at: schema.updated_at
    }

    MapperHelpers.from_persistence!(BehavioralNote, attrs, schema.id)
  end

  @doc "Converts a BehavioralNote domain model to attributes for persistence."
  @spec to_persistence(BehavioralNote.t()) :: map()
  def to_persistence(%BehavioralNote{} = note) do
    %{
      id: note.id,
      participation_record_id: note.participation_record_id,
      child_id: note.child_id,
      parent_id: note.parent_id,
      provider_id: note.provider_id,
      content: note.content,
      status: note.status,
      rejection_reason: note.rejection_reason,
      submitted_at: note.submitted_at,
      reviewed_at: note.reviewed_at
    }
  end

  @doc "Updates a schema struct with domain model values for update operations."
  @spec update_schema(BehavioralNoteSchema.t(), BehavioralNote.t()) :: map()
  def update_schema(%BehavioralNoteSchema{}, %BehavioralNote{} = note) do
    %{
      content: note.content,
      status: note.status,
      rejection_reason: note.rejection_reason,
      submitted_at: note.submitted_at,
      reviewed_at: note.reviewed_at
    }
  end
end
