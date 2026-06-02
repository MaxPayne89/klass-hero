defmodule KlassHero.Provider.Adapters.Driven.Persistence.Mappers.IncidentReportSummaryMapperTest do
  @moduledoc """
  Unit tests for IncidentReportSummaryMapper.

  Covers schema-to-read-model projection, verifying all display fields are
  mapped correctly and that optional FK fields (program_id, session_id) are
  guarded against nil. No database required.
  """

  use ExUnit.Case, async: true

  alias KlassHero.Provider.Adapters.Driven.Persistence.Mappers.IncidentReportSummaryMapper
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.IncidentReportSchema
  alias KlassHero.Provider.Domain.ReadModels.IncidentReportSummary

  @id Ecto.UUID.generate()
  @provider_id Ecto.UUID.generate()
  @program_id Ecto.UUID.generate()

  defp valid_schema(overrides \\ %{}) do
    defaults = %{
      id: @id,
      provider_id: @provider_id,
      reporter_user_id: Ecto.UUID.generate(),
      reporter_display_name: "Jane Smith",
      program_id: @program_id,
      session_id: nil,
      category: :safety_concern,
      severity: :medium,
      description: "Child fell off equipment",
      occurred_at: ~U[2025-03-15 14:30:00Z],
      photo_url: nil,
      original_filename: nil,
      inserted_at: ~U[2025-03-15 15:00:00Z],
      updated_at: ~U[2025-03-15 15:00:00Z]
    }

    struct!(IncidentReportSchema, Map.merge(defaults, overrides))
  end

  describe "from_schema/1" do
    test "maps all display fields to the read model struct" do
      schema = valid_schema()

      summary = IncidentReportSummaryMapper.from_schema(schema)

      assert %IncidentReportSummary{} = summary
      assert summary.id == @id
      assert summary.provider_id == @provider_id
      assert summary.program_id == @program_id
      assert summary.reporter_display_name == "Jane Smith"
      assert summary.category == :safety_concern
      assert summary.severity == :medium
      assert summary.description == "Child fell off equipment"
      assert summary.occurred_at == ~U[2025-03-15 14:30:00Z]
    end

    test "maps nil program_id to nil" do
      schema = valid_schema(%{program_id: nil})

      summary = IncidentReportSummaryMapper.from_schema(schema)

      assert is_nil(summary.program_id)
    end

    test "converts non-nil program_id UUID to string" do
      schema = valid_schema(%{program_id: @program_id})

      summary = IncidentReportSummaryMapper.from_schema(schema)

      assert summary.program_id == @program_id
    end

    test "maps nil session_id to nil" do
      schema = valid_schema(%{session_id: nil})

      summary = IncidentReportSummaryMapper.from_schema(schema)

      assert is_nil(summary.session_id)
    end

    test "converts non-nil session_id UUID to string" do
      session_id = Ecto.UUID.generate()
      schema = valid_schema(%{program_id: nil, session_id: session_id})

      summary = IncidentReportSummaryMapper.from_schema(schema)

      assert summary.session_id == session_id
    end
  end
end
