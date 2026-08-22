defmodule KlassHero.Provider.ReadModels.IncidentReportSummaryTest do
  @moduledoc """
  Covers the struct's shape and `from_report/1`'s narrowing of an
  `IncidentReport`: every display field projected, optional FKs guarded against
  nil, `reporter_user_id` deliberately absent. No database required.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias KlassHero.Provider.IncidentReport
  alias KlassHero.Provider.ReadModels.IncidentReportSummary

  @id Ecto.UUID.generate()
  @provider_id Ecto.UUID.generate()
  @program_id Ecto.UUID.generate()
  @session_id Ecto.UUID.generate()

  @categories [:safety_concern, :behavioral_issue, :injury, :property_damage, :policy_violation, :other]
  @severities [:low, :medium, :high, :critical]

  defp valid_report(overrides \\ %{}) do
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

  describe "struct" do
    test "exposes the fields needed for the program incidents listing" do
      summary = %IncidentReportSummary{
        id: "report-1",
        provider_id: "prov-1",
        program_id: "prog-1",
        session_id: nil,
        category: :safety_concern,
        severity: :high,
        description: "A child slipped near the play area but is unharmed.",
        occurred_at: ~U[2026-04-20 14:30:00Z],
        reporter_display_name: "Jane Doe"
      }

      assert summary.id == "report-1"
      assert summary.reporter_display_name == "Jane Doe"
      assert summary.category == :safety_concern
      assert summary.severity == :high
    end

    test "enforces required keys" do
      assert_raise ArgumentError, fn ->
        struct!(IncidentReportSummary, %{id: "x"})
      end
    end
  end

  describe "from_report/1" do
    test "projects every display field" do
      summary = IncidentReportSummary.from_report(valid_report())

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

    # The reason the summary exists: reporter identity is a submit-time snapshot,
    # so the live FK must not reach a display struct.
    test "drops reporter_user_id" do
      refute Map.has_key?(IncidentReportSummary.from_report(valid_report()), :reporter_user_id)
    end

    for {field, value} <- [program_id: @program_id, session_id: @session_id] do
      test "guards a nil #{field} and stringifies it otherwise" do
        field = unquote(field)

        assert valid_report(%{field => nil}) |> IncidentReportSummary.from_report() |> Map.fetch!(field) == nil

        assert valid_report(%{field => unquote(value)})
               |> IncidentReportSummary.from_report()
               |> Map.fetch!(field) == unquote(value)
      end
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
        summary =
          IncidentReportSummary.from_report(
            valid_report(%{
              id: id,
              provider_profile_id: provider_id,
              program_id: program_id,
              session_id: session_id,
              category: category,
              severity: severity,
              description: description,
              reporter_display_name: reporter_display_name
            })
          )

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
