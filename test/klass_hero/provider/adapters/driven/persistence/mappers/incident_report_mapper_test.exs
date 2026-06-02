defmodule KlassHero.Provider.Adapters.Driven.Persistence.Mappers.IncidentReportMapperTest do
  @moduledoc """
  Unit tests for IncidentReportMapper.

  Covers bidirectional mapping between IncidentReport domain model and
  IncidentReportSchema, with emphasis on the provider_profile_id ↔ provider_id
  field-name translation and nil-guard behaviour for optional FK fields.
  No database required.
  """

  use ExUnit.Case, async: true

  alias KlassHero.Provider.Adapters.Driven.Persistence.Mappers.IncidentReportMapper
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.IncidentReportSchema
  alias KlassHero.Provider.Domain.Models.IncidentReport

  @id Ecto.UUID.generate()
  @provider_id Ecto.UUID.generate()
  @reporter_user_id Ecto.UUID.generate()
  @program_id Ecto.UUID.generate()

  defp valid_schema(overrides \\ %{}) do
    defaults = %{
      id: @id,
      provider_id: @provider_id,
      reporter_user_id: @reporter_user_id,
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

  defp valid_domain(overrides \\ %{}) do
    defaults = %{
      id: @id,
      provider_profile_id: @provider_id,
      reporter_user_id: @reporter_user_id,
      reporter_display_name: "Jane Smith",
      program_id: @program_id,
      session_id: nil,
      category: :safety_concern,
      severity: :medium,
      description: "Child fell off equipment",
      occurred_at: ~U[2025-03-15 14:30:00Z],
      photo_url: nil,
      original_filename: nil
    }

    struct!(IncidentReport, Map.merge(defaults, overrides))
  end

  describe "to_domain/1" do
    test "maps all required fields from schema to domain struct" do
      schema = valid_schema()

      report = IncidentReportMapper.to_domain(schema)

      assert %IncidentReport{} = report
      assert report.id == @id
      assert report.reporter_user_id == @reporter_user_id
      assert report.reporter_display_name == "Jane Smith"
      assert report.category == :safety_concern
      assert report.severity == :medium
      assert report.description == "Child fell off equipment"
      assert report.occurred_at == ~U[2025-03-15 14:30:00Z]
    end

    test "translates provider_id (DB) to provider_profile_id (domain)" do
      schema = valid_schema()

      report = IncidentReportMapper.to_domain(schema)

      assert report.provider_profile_id == @provider_id
    end

    test "preserves timestamps from schema" do
      schema = valid_schema()

      report = IncidentReportMapper.to_domain(schema)

      assert report.inserted_at == ~U[2025-03-15 15:00:00Z]
      assert report.updated_at == ~U[2025-03-15 15:00:00Z]
    end

    test "maps nil program_id to nil" do
      schema = valid_schema(%{program_id: nil})

      report = IncidentReportMapper.to_domain(schema)

      assert is_nil(report.program_id)
    end

    test "converts non-nil program_id UUID to string" do
      schema = valid_schema(%{program_id: @program_id})

      report = IncidentReportMapper.to_domain(schema)

      assert report.program_id == @program_id
    end

    test "maps nil session_id to nil" do
      schema = valid_schema(%{session_id: nil})

      report = IncidentReportMapper.to_domain(schema)

      assert is_nil(report.session_id)
    end

    test "converts non-nil session_id UUID to string" do
      session_id = Ecto.UUID.generate()
      schema = valid_schema(%{program_id: nil, session_id: session_id})

      report = IncidentReportMapper.to_domain(schema)

      assert report.session_id == session_id
    end

    test "maps nil photo_url to nil" do
      schema = valid_schema(%{photo_url: nil})

      report = IncidentReportMapper.to_domain(schema)

      assert is_nil(report.photo_url)
    end

    test "passes through non-nil photo_url and original_filename" do
      schema = valid_schema(%{photo_url: "photos/report-abc.jpg", original_filename: "photo.jpg"})

      report = IncidentReportMapper.to_domain(schema)

      assert report.photo_url == "photos/report-abc.jpg"
      assert report.original_filename == "photo.jpg"
    end
  end

  describe "to_schema/1" do
    test "maps all required fields from domain to attribute map" do
      domain = valid_domain()

      attrs = IncidentReportMapper.to_schema(domain)

      assert attrs.id == @id
      assert attrs.reporter_user_id == @reporter_user_id
      assert attrs.reporter_display_name == "Jane Smith"
      assert attrs.category == :safety_concern
      assert attrs.severity == :medium
      assert attrs.description == "Child fell off equipment"
      assert attrs.occurred_at == ~U[2025-03-15 14:30:00Z]
    end

    test "translates provider_profile_id (domain) to provider_id (DB)" do
      domain = valid_domain()

      attrs = IncidentReportMapper.to_schema(domain)

      assert attrs.provider_id == @provider_id
      refute Map.has_key?(attrs, :provider_profile_id)
    end

    test "maps nil program_id and session_id to nil" do
      domain = valid_domain(%{program_id: nil, session_id: nil})

      attrs = IncidentReportMapper.to_schema(domain)

      assert is_nil(attrs.program_id)
      assert is_nil(attrs.session_id)
    end

    test "maps non-nil session_id through" do
      session_id = Ecto.UUID.generate()
      domain = valid_domain(%{program_id: nil, session_id: session_id})

      attrs = IncidentReportMapper.to_schema(domain)

      assert is_nil(attrs.program_id)
      assert attrs.session_id == session_id
    end

    test "maps nil photo fields to nil" do
      domain = valid_domain(%{photo_url: nil, original_filename: nil})

      attrs = IncidentReportMapper.to_schema(domain)

      assert is_nil(attrs.photo_url)
      assert is_nil(attrs.original_filename)
    end

    test "maps non-nil photo fields through" do
      domain = valid_domain(%{photo_url: "photos/report-abc.jpg", original_filename: "photo.jpg"})

      attrs = IncidentReportMapper.to_schema(domain)

      assert attrs.photo_url == "photos/report-abc.jpg"
      assert attrs.original_filename == "photo.jpg"
    end

    test "does not include timestamps" do
      domain = valid_domain()

      attrs = IncidentReportMapper.to_schema(domain)

      refute Map.has_key?(attrs, :inserted_at)
      refute Map.has_key?(attrs, :updated_at)
    end
  end

  describe "round-trip" do
    test "domain → schema attrs → domain preserves all fields" do
      domain_before =
        valid_domain(%{photo_url: "photos/test.jpg", original_filename: "test.jpg"})

      attrs = IncidentReportMapper.to_schema(domain_before)

      schema =
        struct!(IncidentReportSchema, Map.merge(Map.from_struct(valid_schema()), attrs))

      domain_after = IncidentReportMapper.to_domain(schema)

      assert domain_after.id == domain_before.id
      assert domain_after.provider_profile_id == domain_before.provider_profile_id
      assert domain_after.reporter_user_id == domain_before.reporter_user_id
      assert domain_after.category == domain_before.category
      assert domain_after.severity == domain_before.severity
      assert domain_after.description == domain_before.description
      assert domain_after.photo_url == domain_before.photo_url
      assert domain_after.original_filename == domain_before.original_filename
    end
  end
end
