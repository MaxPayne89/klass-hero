defmodule KlassHero.Provider.NotifyIncidentReportedWorkerTest do
  @moduledoc """
  Tests for the NotifyIncidentReportedWorker Oban worker.

  The worker is a thin shell over the NotifyIncidentReported use case —
  it deserialises `incident_report_id`, `business_owner_email` and
  `business_name` from JSON args and propagates the use case's return
  value so Oban can decide whether to retry.
  """

  use KlassHero.DataCase, async: false

  import KlassHero.AccountsFixtures, only: [unconfirmed_user_fixture: 1]
  import KlassHero.EmailTestHelper
  import KlassHero.Factory
  import KlassHero.ProviderFixtures
  import Swoosh.TestAssertions

  alias KlassHero.Provider.NotifyIncidentReportedWorker

  setup do
    flush_emails()
    :ok
  end

  describe "perform/1" do
    test "forwards business_owner_email + business_name from args to the use case" do
      owner = unconfirmed_user_fixture(intended_roles: [:provider])
      reporter = unconfirmed_user_fixture(intended_roles: [:provider])

      provider =
        provider_profile_fixture(
          identity_id: owner.id,
          business_name: "Profile Name (should be ignored)",
          business_owner_email: "profile-owner@example.com"
        )

      program = insert(:program_schema, provider_id: provider.id, title: "Worker Program")

      report =
        incident_report_fixture(%{
          provider_profile_id: provider.id,
          reporter_user_id: reporter.id,
          program_id: program.id,
          description: "Worker test incident description."
        })

      # Mismatched values prove the worker forwards args (not falling back to
      # the profile DB row, which has different values).
      job = %Oban.Job{
        args: %{
          "incident_report_id" => report.id,
          "business_owner_email" => "args-owner@example.com",
          "business_name" => "Args Business"
        },
        queue: "email",
        attempt: 1,
        max_attempts: 3
      }

      assert :ok = NotifyIncidentReportedWorker.perform(job)

      assert_email_sent(fn email ->
        assert email.to == [{"Args Business", "args-owner@example.com"}]
        assert email.subject =~ "Worker Program"
      end)
    end

    test "propagates :incident_report_not_found error for unknown ids" do
      job = %Oban.Job{
        args: %{
          "incident_report_id" => Ecto.UUID.generate(),
          "business_owner_email" => "owner@example.com",
          "business_name" => "Acme"
        },
        queue: "email",
        attempt: 1,
        max_attempts: 3
      }

      assert {:error, :incident_report_not_found} =
               NotifyIncidentReportedWorker.perform(job)

      assert_no_email_sent()
    end
  end
end
