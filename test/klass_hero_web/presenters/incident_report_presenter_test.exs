defmodule KlassHeroWeb.Presenters.IncidentReportPresenterTest do
  use ExUnit.Case, async: true

  alias KlassHero.Provider.ReadModels.IncidentReportSummary
  alias KlassHeroWeb.Presenters.IncidentReportPresenter

  # Single source of truth for the finite enum→display lookups, shared between
  # the standalone severity_color/1 tests and the to_list_view/1 tests.
  @severity_colors [critical: "error", high: "warning", medium: "info", low: "success"]
  @severity_labels [low: "Low", medium: "Medium", high: "High", critical: "Critical"]
  @category_labels [
    safety_concern: "Safety concern",
    behavioral_issue: "Behavioral issue",
    injury: "Injury",
    property_damage: "Property damage",
    policy_violation: "Policy violation",
    other: "Other"
  ]

  defp build_summary(overrides \\ %{}) do
    defaults = %{
      id: "report-1",
      provider_id: "prov-1",
      program_id: "prog-1",
      session_id: nil,
      category: :injury,
      severity: :medium,
      description: "Child scraped knee on playground.",
      occurred_at: ~U[2024-06-15 09:30:00Z],
      reporter_display_name: "Coach Anna"
    }

    struct!(IncidentReportSummary, Map.merge(defaults, overrides))
  end

  describe "severity_color/1" do
    for {severity, color} <- @severity_colors do
      @severity severity
      @color color
      test "#{severity} -> #{color}" do
        assert IncidentReportPresenter.severity_color(@severity) == @color
      end
    end
  end

  describe "to_list_view/1" do
    test "returns a map with all expected keys" do
      result = IncidentReportPresenter.to_list_view(build_summary())

      assert Map.keys(result) |> Enum.sort() ==
               [
                 :category_label,
                 :description,
                 :id,
                 :occurred_at_display,
                 :reporter_display_name,
                 :severity_color,
                 :severity_label
               ]
    end

    test "preserves id, description, and reporter_display_name unchanged" do
      summary =
        build_summary(%{id: "rpt-42", description: "Fire alarm activated.", reporter_display_name: "Max Mustermann"})

      result = IncidentReportPresenter.to_list_view(summary)

      assert result.id == "rpt-42"
      assert result.description == "Fire alarm activated."
      assert result.reporter_display_name == "Max Mustermann"
    end

    for {category, label} <- @category_labels do
      @category category
      @label label
      test "category #{category} -> #{inspect(label)}" do
        result = IncidentReportPresenter.to_list_view(build_summary(%{category: @category}))
        assert result.category_label == @label
      end
    end

    for {severity, label} <- @severity_labels do
      @severity severity
      @label label
      test "severity #{severity} -> label #{inspect(label)}" do
        result = IncidentReportPresenter.to_list_view(build_summary(%{severity: @severity}))
        assert result.severity_label == @label
      end
    end

    for {severity, color} <- @severity_colors do
      @severity severity
      @color color
      test "severity #{severity} -> color #{inspect(color)}" do
        result = IncidentReportPresenter.to_list_view(build_summary(%{severity: @severity}))
        assert result.severity_color == @color
      end
    end

    # {occurred_at, expected display} — a normal timestamp, nil, and the midnight boundary.
    @occurred_at_cases [
      {~U[2024-03-21 14:05:00Z], "2024-03-21 14:05"},
      {nil, ""},
      {~U[2025-01-01 00:00:00Z], "2025-01-01 00:00"}
    ]

    for {occurred_at, expected} <- @occurred_at_cases do
      @occurred_at occurred_at
      @expected expected
      test "occurred_at #{inspect(occurred_at)} -> #{inspect(expected)}" do
        result = IncidentReportPresenter.to_list_view(build_summary(%{occurred_at: @occurred_at}))
        assert result.occurred_at_display == @expected
      end
    end
  end
end
