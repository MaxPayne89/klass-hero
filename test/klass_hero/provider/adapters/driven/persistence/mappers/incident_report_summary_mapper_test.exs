defmodule KlassHero.Provider.Adapters.Driven.Persistence.Mappers.IncidentReportSummaryMapperTest do
  @moduledoc """
  Unit tests for IncidentReportSummaryMapper.

  Covers schema-to-read-model projection, verifying all display fields are
  mapped correctly and that optional FK fields (program_id, session_id) are
  guarded against nil. No database required.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias KlassHero.Provider.Adapters.Driven.Persistence.Mappers.IncidentReportSummaryMapper
  alias KlassHero.Provider.Domain.ReadModels.IncidentReportSummary
  alias KlassHero.Provider.IncidentReport

  @id Ecto.UUID.generate()
  @provider_id Ecto.UUID.generate()
  @program_id Ecto.UUID.generate()

  @categories [:safety_concern, :behavioral_issue, :injury, :property_damage, :policy_violation, :other]
  @severities [:low, :medium, :high, :critical]

  defp valid_schema(overrides \\ %{}) do
    defaults = %{
      id: @id,
      provider_profile_id: @provider_id,
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

    struct!(IncidentReport, Map.merge(defaults, overrides))
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

    property "projects every display field, stringifying ids and guarding nil FKs" do
      check all(
              id <- nonempty_string(),
              provider_id <- nonempty_string(),
              program_id <- maybe(nonempty_string()),
              session_id <- maybe(nonempty_string()),
              category <- member_of(@categories),
              severity <- member_of(@severities),
              description <- nonempty_string(),
              reporter_display_name <- nonempty_string()
            ) do
        schema =
          valid_schema(%{
            id: id,
            provider_profile_id: provider_id,
            program_id: program_id,
            session_id: session_id,
            category: category,
            severity: severity,
            description: description,
            reporter_display_name: reporter_display_name
          })

        summary = IncidentReportSummaryMapper.from_schema(schema)

        assert summary.id == to_string(id)
        assert summary.provider_id == to_string(provider_id)
        assert summary.program_id == maybe_to_string(program_id)
        assert summary.session_id == maybe_to_string(session_id)
        assert summary.category == category
        assert summary.severity == severity
        assert summary.description == description
        assert summary.reporter_display_name == reporter_display_name
      end
    end
  end

  defp maybe(gen), do: one_of([constant(nil), gen])
  defp nonempty_string, do: string(:alphanumeric, min_length: 1, max_length: 20)
  defp maybe_to_string(nil), do: nil
  defp maybe_to_string(value), do: to_string(value)
end
