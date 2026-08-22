defmodule KlassHero.Provider.Incidents.NotifyIncidentReportedTest do
  @moduledoc """
  Tests for the NotifyIncidentReported use case.

  Uses real adapters with the test DB and the Swoosh test mailer adapter,
  matching the convention of other Provider use case tests. Email assertions
  use `Swoosh.TestAssertions`.

  The use case is payload-driven: `business_owner_email` and `business_name`
  arrive in the args (forwarded by the Oban worker from the enqueued job).
  No profile DB lookup happens here; that responsibility lives in
  `SubmitIncidentReport`.
  """

  use KlassHero.DataCase, async: false

  import KlassHero.AccountsFixtures, only: [unconfirmed_user_fixture: 1]
  import KlassHero.EmailTestHelper
  import KlassHero.Factory
  import KlassHero.ProviderFixtures
  import Swoosh.TestAssertions

  alias KlassHero.Provider.NotifyIncidentReported
  alias KlassHero.Shared.Adapters.Driven.Storage.StubStorageAdapter

  setup do
    flush_emails()

    owner = unconfirmed_user_fixture(intended_roles: [:provider])
    reporter = unconfirmed_user_fixture(intended_roles: [:provider])

    provider =
      provider_profile_fixture(
        identity_id: owner.id,
        business_name: "Acme Adventures",
        business_owner_email: "owner@example.com"
      )

    program = insert(:program_schema, provider_id: provider.id)

    provider_program_projection_fixture(
      provider_id: provider.id,
      program_id: program.id,
      name: "Climbing Club"
    )

    %{owner: owner, reporter: reporter, provider: provider, program: program}
  end

  describe "execute/1 — happy path" do
    test "uses business_owner_email + business_name from args, not the profile DB row",
         %{provider: provider, program: program, reporter: reporter} do
      report =
        incident_report_fixture(%{
          provider_profile_id: provider.id,
          reporter_user_id: reporter.id,
          program_id: program.id
        })

      # Mismatched values prove the use case reads the args, not the profile DB row.
      args =
        notify_args(report, provider,
          business_owner_email: "args-owner@example.com",
          business_name: "Args Business Name"
        )

      assert :ok = NotifyIncidentReported.execute(args)

      assert_email_sent(fn email ->
        assert email.to == [{"Args Business Name", "args-owner@example.com"}]
        assert email.subject =~ "Climbing Club"
        assert email.subject =~ "Safety concern"
        assert email.text_body =~ report.description
        assert email.text_body =~ report.id
      end)
    end
  end

  describe "execute/1 — incident report missing" do
    test "returns :incident_report_not_found when the id does not exist" do
      assert {:error, :incident_report_not_found} =
               NotifyIncidentReported.execute(%{
                 incident_report_id: Ecto.UUID.generate(),
                 business_owner_email: "owner@example.com",
                 business_name: "Acme Adventures"
               })

      assert_no_email_sent()
    end
  end

  describe "execute/1 — program lookup fallback" do
    test "still sends email with fallback label when the program projection is missing", %{
      provider: provider,
      reporter: reporter
    } do
      # Trigger: program exists in :programs table (FK satisfied) but the
      #         provider-local projection row was never inserted
      # Why: Programs.get_provider_program/1 returns {:error, :not_found}
      #      whenever the provider_programs projection row is missing
      # Outcome: use case must not fail — falls back to "a program" label
      unprojected_program = insert(:program_schema, provider_id: provider.id)

      report =
        incident_report_fixture(%{
          provider_profile_id: provider.id,
          reporter_user_id: reporter.id,
          program_id: unprojected_program.id
        })

      assert :ok = NotifyIncidentReported.execute(notify_args(report, provider))

      assert_email_sent(fn email ->
        email.subject =~ "a program" and email.text_body =~ "a program"
      end)
    end
  end

  describe "execute/1 — session-scoped report" do
    test "uses 'a session' label when the report is session-scoped", %{
      provider: provider,
      program: program,
      reporter: reporter
    } do
      session = insert(:program_session_schema, program_id: program.id)

      report =
        incident_report_fixture(%{
          provider_profile_id: provider.id,
          reporter_user_id: reporter.id,
          session_id: session.id
        })

      assert :ok = NotifyIncidentReported.execute(notify_args(report, provider))

      assert_email_sent(fn email ->
        assert email.subject =~ "a session"
        assert email.text_body =~ "a session"
      end)
    end
  end

  describe "execute/1 — photo signing" do
    test "sends a no-photo email when signed_url fails", %{
      provider: provider,
      program: program,
      reporter: reporter
    } do
      report =
        incident_report_fixture(%{
          provider_profile_id: provider.id,
          reporter_user_id: reporter.id,
          program_id: program.id,
          photo_url: "incident-reports/providers/#{provider.id}/missing.jpg",
          original_filename: "missing.jpg"
        })

      assert :ok = NotifyIncidentReported.execute(notify_args(report, provider))

      assert_email_sent(fn email ->
        not (email.text_body =~ "View photo") and not (email.html_body =~ "View photo")
      end)
    end

    test "includes the signed URL when signing succeeds", %{
      provider: provider,
      program: program,
      reporter: reporter
    } do
      photo_key = "incident-reports/providers/#{provider.id}/incident.jpg"

      # Pre-upload the file so signed_url returns {:ok, url}
      {:ok, ^photo_key} = StubStorageAdapter.upload(:private, photo_key, "fake-bytes", [])

      report =
        incident_report_fixture(%{
          provider_profile_id: provider.id,
          reporter_user_id: reporter.id,
          program_id: program.id,
          photo_url: photo_key,
          original_filename: "incident.jpg"
        })

      assert :ok = NotifyIncidentReported.execute(notify_args(report, provider))

      assert_email_sent(fn email ->
        assert email.text_body =~ "stub://signed/"
        assert email.html_body =~ "View photo"
      end)
    end
  end

  # Builds the worker-shaped args map. Defaults pull straight from the
  # provider record so tests stay in sync with whatever `setup` actually
  # created. Tests that exercise mismatched values pass overrides via opts.
  defp notify_args(report, provider, opts \\ []) do
    %{
      incident_report_id: report.id,
      business_owner_email: Keyword.get(opts, :business_owner_email, provider.business_owner_email),
      business_name: Keyword.get(opts, :business_name, provider.business_name)
    }
  end
end
