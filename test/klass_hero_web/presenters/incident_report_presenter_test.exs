defmodule KlassHeroWeb.Presenters.IncidentReportPresenterTest do
  use ExUnit.Case, async: true

  alias KlassHero.Provider.Domain.ReadModels.IncidentReportSummary
  alias KlassHeroWeb.Presenters.IncidentReportPresenter

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
    test "critical maps to error" do
      assert IncidentReportPresenter.severity_color(:critical) == "error"
    end

    test "high maps to warning" do
      assert IncidentReportPresenter.severity_color(:high) == "warning"
    end

    test "medium maps to info" do
      assert IncidentReportPresenter.severity_color(:medium) == "info"
    end

    test "low maps to success" do
      assert IncidentReportPresenter.severity_color(:low) == "success"
    end
  end

  describe "to_list_view/1" do
    test "returns a map with all expected keys" do
      result = IncidentReportPresenter.to_list_view(build_summary())

      assert Map.keys(result) |> Enum.sort() ==
               [:category_label, :description, :id, :occurred_at_display, :reporter_display_name,
                :severity_color, :severity_label]
    end

    test "preserves id, description, and reporter_display_name unchanged" do
      summary = build_summary(%{id: "rpt-42", description: "Fire alarm activated.", reporter_display_name: "Max Mustermann"})

      result = IncidentReportPresenter.to_list_view(summary)

      assert result.id == "rpt-42"
      assert result.description == "Fire alarm activated."
      assert result.reporter_display_name == "Max Mustermann"
    end

    test "maps category to human-readable label for each valid category" do
      expected = [
        {:safety_concern, "Safety concern"},
        {:behavioral_issue, "Behavioral issue"},
        {:injury, "Injury"},
        {:property_damage, "Property damage"},
        {:policy_violation, "Policy violation"},
        {:other, "Other"}
      ]

      for {category, label} <- expected do
        result = IncidentReportPresenter.to_list_view(build_summary(%{category: category}))
        assert result.category_label == label, "expected #{label} for #{category}"
      end
    end

    test "maps severity to human-readable label for each valid severity" do
      expected = [
        {:low, "Low"},
        {:medium, "Medium"},
        {:high, "High"},
        {:critical, "Critical"}
      ]

      for {severity, label} <- expected do
        result = IncidentReportPresenter.to_list_view(build_summary(%{severity: severity}))
        assert result.severity_label == label, "expected #{label} for #{severity}"
      end
    end

    test "maps severity to correct severity_color for each valid severity" do
      expected = [
        {:critical, "error"},
        {:high, "warning"},
        {:medium, "info"},
        {:low, "success"}
      ]

      for {severity, color} <- expected do
        result = IncidentReportPresenter.to_list_view(build_summary(%{severity: severity}))
        assert result.severity_color == color, "expected #{color} for #{severity}"
      end
    end

    test "formats occurred_at DateTime as YYYY-MM-DD HH:MM" do
      dt = ~U[2024-03-21 14:05:00Z]
      result = IncidentReportPresenter.to_list_view(build_summary(%{occurred_at: dt}))

      assert result.occurred_at_display == "2024-03-21 14:05"
    end

    test "returns empty string for nil occurred_at" do
      summary = build_summary()
      summary_nil = %{summary | occurred_at: nil}

      result = IncidentReportPresenter.to_list_view(summary_nil)

      assert result.occurred_at_display == ""
    end

    test "preserves midnight boundary formatting" do
      dt = ~U[2025-01-01 00:00:00Z]
      result = IncidentReportPresenter.to_list_view(build_summary(%{occurred_at: dt}))

      assert result.occurred_at_display == "2025-01-01 00:00"
    end
  end
end
