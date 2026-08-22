defmodule KlassHero.Provider.Incidents.IncidentReportQueriesTest do
  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures
  import KlassHero.Factory
  import KlassHero.ProviderFixtures

  alias KlassHero.Provider
  alias KlassHero.Provider.ReadModels.IncidentReportSummary

  describe "list_for_program/2" do
    test "delegates to the configured query repository and returns summaries" do
      provider = provider_profile_fixture()
      reporter = unconfirmed_user_fixture(intended_roles: [:provider])
      program = insert(:program_schema, provider_id: provider.id)

      _report =
        incident_report_fixture(
          provider_profile_id: provider.id,
          reporter_user_id: reporter.id,
          program_id: program.id,
          reporter_display_name: "Maria Schmidt"
        )

      assert [%IncidentReportSummary{} = summary] =
               Provider.list_incident_reports_for_program(provider.id, program.id)

      assert summary.reporter_display_name == "Maria Schmidt"
      assert summary.program_id == program.id
    end

    test "returns [] when there are no reports for the program" do
      provider = provider_profile_fixture()
      program = insert(:program_schema, provider_id: provider.id)

      assert Provider.list_incident_reports_for_program(provider.id, program.id) == []
    end
  end
end
