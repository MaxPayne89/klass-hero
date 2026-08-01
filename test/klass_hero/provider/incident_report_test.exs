defmodule KlassHero.Provider.IncidentReportTest do
  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures
  import KlassHero.Factory
  import KlassHero.ProviderFixtures

  alias KlassHero.Provider.IncidentReport

  describe "anonymize_changeset/1" do
    test "replaces the denormalised reporter name with the tombstone" do
      report = incident_report_with_reporter("Jane Whistleblower")

      {:ok, anonymized} = report |> IncidentReport.anonymize_changeset() |> Repo.update()

      assert anonymized.reporter_display_name == IncidentReport.anonymized_attrs().reporter_display_name
      refute anonymized.reporter_display_name =~ "Jane"
    end

    test "keeps the reporter link and the report itself intact" do
      report = incident_report_with_reporter("Jane Whistleblower")

      {:ok, anonymized} = report |> IncidentReport.anonymize_changeset() |> Repo.update()

      # The report is a safety record: it survives erasure, only de-identified.
      assert anonymized.reporter_user_id == report.reporter_user_id
      assert anonymized.description == report.description
      assert anonymized.severity == report.severity
      assert anonymized.occurred_at == report.occurred_at
    end

    test "is idempotent" do
      report = incident_report_with_reporter("Jane Whistleblower")

      {:ok, once} = report |> IncidentReport.anonymize_changeset() |> Repo.update()
      {:ok, twice} = once |> IncidentReport.anonymize_changeset() |> Repo.update()

      assert twice.reporter_display_name == once.reporter_display_name
    end
  end

  defp incident_report_with_reporter(display_name) do
    provider = provider_profile_fixture()
    reporter = unconfirmed_user_fixture(intended_roles: [:provider])
    program = insert(:program_schema, provider_id: provider.id)

    incident_report_fixture(
      provider_profile_id: provider.id,
      reporter_user_id: reporter.id,
      reporter_display_name: display_name,
      program_id: program.id
    )
  end
end
