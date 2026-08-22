defmodule KlassHero.Provider.ReplayStandingAssignmentsWorkerTest do
  use KlassHero.DataCase, async: false
  use Oban.Testing, repo: KlassHero.Repo

  import KlassHero.EventTestHelper
  import KlassHero.Factory

  alias KlassHero.Provider.ReplayStandingAssignmentsWorker

  setup do
    setup_test_integration_events()
    :ok
  end

  test "perform/1 stages the replay for a staff member who already claimed" do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)

    staff =
      insert(:staff_member_schema,
        provider_id: provider.id,
        user_id: KlassHero.AccountsFixtures.user_fixture().id
      )

    insert(:program_staff_assignment_schema,
      provider_id: provider.id,
      program_id: program.id,
      staff_member_id: staff.id
    )

    clear_integration_events()

    assert :ok = perform_job(ReplayStandingAssignmentsWorker, %{})

    event = assert_integration_event_published(:staff_assigned_to_program)
    assert event.payload.staff_user_id == staff.user_id
  end

  test "perform/1 succeeds with nothing to repair" do
    assert :ok = perform_job(ReplayStandingAssignmentsWorker, %{})
    assert_no_integration_events_published()
  end
end
