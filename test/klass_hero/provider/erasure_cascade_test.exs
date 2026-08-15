defmodule KlassHero.Provider.ErasureCascadeTest do
  @moduledoc """
  End-to-end proof that account deletion actually reaches the Provider context.

  Every other test in this feature calls the handler or use case directly. This
  one starts at `Accounts.delete_account/2` and lets the real machinery run:
  staged event → Oban job → consumer registry → `ProviderEventHandler`. It is
  the test that would have caught the original bug, where the handler was wired
  up correctly and simply did nothing.
  """
  # async: false — swaps the :outbox adapter in application env, which every
  # other test reads (see outbox_test.exs for the same constraint).
  use KlassHero.DataCase, async: false

  import KlassHero.AccountsFixtures
  import KlassHero.Factory
  import KlassHero.ProviderFixtures

  alias KlassHero.Accounts
  alias KlassHero.Provider
  alias KlassHero.Provider.IncidentReport
  alias KlassHero.Provider.StaffMember
  alias KlassHero.Shared.Adapters.Driven.Events.ObanOutbox

  setup do
    original = Application.get_env(:klass_hero, :outbox)
    Application.put_env(:klass_hero, :outbox, module: ObanOutbox)
    on_exit(fn -> Application.put_env(:klass_hero, :outbox, original) end)
  end

  test "deleting an account scrubs Provider-owned PII through the real event path" do
    # delete_account/2 gates on sudo mode: a recent authenticated_at plus the password.
    user =
      [intended_roles: [:staff, :provider]]
      |> user_fixture()
      |> set_password()

    user = %{user | authenticated_at: DateTime.utc_now(:second)}

    # With the real outbox, registering the user already drove :user_registered
    # through this same handler, which created the profile.
    {:ok, provider} = Provider.get_provider_by_identity(user.id)

    program = insert(:program_schema, provider_id: provider.id)

    staff =
      staff_member_fixture(
        provider_id: provider.id,
        user_id: user.id,
        first_name: "Jane",
        last_name: "Whistleblower",
        email: "jane@example.com"
      )

    report =
      incident_report_fixture(
        provider_profile_id: provider.id,
        reporter_user_id: user.id,
        reporter_display_name: "Jane Whistleblower",
        program_id: program.id
      )

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, _anonymized_user} = Accounts.delete_account(user, valid_user_password())

      # Nothing has consumed the event yet — the job is staged, not run.
      assert Repo.get(StaffMember, staff.id).email == "jane@example.com"

      Oban.drain_queue(queue: :events, with_recursion: true)
    end)

    scrubbed_staff = Repo.get(StaffMember, staff.id)
    assert StaffMember.full_name(scrubbed_staff) == "Deleted User"
    assert scrubbed_staff.email == nil
    refute scrubbed_staff.active

    assert Repo.get(IncidentReport, report.id).reporter_display_name ==
             IncidentReport.anonymized_attrs().reporter_display_name
  end
end
