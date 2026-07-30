defmodule KlassHero.Messaging.Adapters.Driven.Projections.EnrolledChildrenTest do
  use KlassHero.DataCase, async: false

  import Ecto.Query
  import ExUnit.CaptureLog
  import KlassHero.Factory

  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.EnrolledChildrenSchema
  alias KlassHero.Messaging.Adapters.Driven.Projections.EnrolledChildren
  alias KlassHero.Repo
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  @test_server_name :enrolled_children_projection_test

  setup do
    pid = start_supervised!({EnrolledChildren, name: @test_server_name})
    # Drain bootstrap (runs in handle_continue) so later broadcasts are what we measure
    _ = :sys.get_state(@test_server_name)
    {:ok, pid: pid}
  end

  describe "bootstrap" do
    test "projects existing enrollments into messaging_enrolled_children on startup" do
      user = user_fixture(name: "Sarah Johnson")
      parent = insert(:parent_profile_schema, identity_id: user.id)
      child = insert(:child_schema, first_name: "Emma", last_name: "Johnson")
      insert(:child_guardian_schema, child_id: child.id, guardian_id: parent.id)
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)

      insert(:enrollment_schema,
        parent_id: parent.id,
        child_id: child.id,
        program_id: program.id,
        status: "confirmed"
      )

      EnrolledChildren.rebuild(@test_server_name)

      rows =
        from(e in EnrolledChildrenSchema,
          where: e.parent_user_id == ^user.id and e.program_id == ^program.id
        )
        |> Repo.all()

      assert length(rows) == 1
      [row] = rows
      assert row.child_id == child.id
      assert row.child_first_name == "Emma"
    end

    test "ignores cancelled enrollments during bootstrap" do
      user = user_fixture(name: "Bob Smith")
      parent = insert(:parent_profile_schema, identity_id: user.id)
      child = insert(:child_schema, first_name: "Max")
      insert(:child_guardian_schema, child_id: child.id, guardian_id: parent.id)
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)

      insert(:enrollment_schema,
        parent_id: parent.id,
        child_id: child.id,
        program_id: program.id,
        status: "cancelled"
      )

      EnrolledChildren.rebuild(@test_server_name)

      count =
        from(e in EnrolledChildrenSchema, where: e.parent_user_id == ^user.id)
        |> Repo.aggregate(:count)

      assert count == 0
    end
  end

  describe "handle enrollment_created event" do
    test "resolves child_first_name from children table on insert" do
      user = user_fixture(name: "Sarah Johnson")
      parent = insert(:parent_profile_schema, identity_id: user.id)
      child = insert(:child_schema, first_name: "Emma", last_name: "Johnson")
      insert(:child_guardian_schema, child_id: child.id, guardian_id: parent.id)
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      enrollment_id = Ecto.UUID.generate()

      event =
        IntegrationEvent.new(
          :enrollment_created,
          :enrollment,
          :enrollment,
          enrollment_id,
          %{
            enrollment_id: enrollment_id,
            child_id: child.id,
            parent_id: parent.id,
            parent_user_id: user.id,
            program_id: program.id,
            status: "confirmed"
          }
        )

      EnrolledChildren.project(event)

      row =
        Repo.one(
          from(e in EnrolledChildrenSchema,
            where: e.parent_user_id == ^user.id and e.program_id == ^program.id
          )
        )

      assert row != nil
      assert row.child_id == child.id
      assert row.child_first_name == "Emma"
    end

    test "inserts row with nil child_first_name and logs warning when child row is missing" do
      user = user_fixture(name: "Unknown Parent")
      parent = insert(:parent_profile_schema, identity_id: user.id)
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)

      missing_child_id = Ecto.UUID.generate()
      enrollment_id = Ecto.UUID.generate()

      event =
        IntegrationEvent.new(
          :enrollment_created,
          :enrollment,
          :enrollment,
          enrollment_id,
          %{
            enrollment_id: enrollment_id,
            child_id: missing_child_id,
            parent_id: parent.id,
            parent_user_id: user.id,
            program_id: program.id,
            status: "confirmed"
          }
        )

      log =
        capture_log(fn ->
          EnrolledChildren.project(event)
        end)

      assert log =~ "child row not found"

      row =
        Repo.one(
          from(e in EnrolledChildrenSchema,
            where: e.parent_user_id == ^user.id and e.program_id == ^program.id
          )
        )

      assert row != nil
      assert row.child_first_name == nil
    end
  end

  describe "macro invariants after happy-path startup" do
    test "state.retry_count == 0 after first event projects successfully" do
      # Start WITHOUT skip_bootstrap to exercise the real subscribe + handle_continue path.
      # If a KeyError-class bug got swallowed by the retry mixin's rescue, retry_count
      # would be > 0 even though the test event still projects correctly.
      pid =
        start_supervised!(
          {EnrolledChildren, name: :"reg_#{System.unique_integer([:positive])}"},
          id: :regression_projection
        )

      # Drain handle_continue; bootstrap should succeed on the first attempt.
      # Shared sandbox (async: false) covers the GenServer pid automatically.
      :sys.get_state(pid)

      # If any rescue path was triggered during bootstrap, retry_count would be > 0.
      assert %{bootstrapped: true, retry_count: 0} = :sys.get_state(pid)

      # Send one well-formed enrollment_created event; confirm dispatcher path
      # doesn't trip an internal raise.
      enrollment_id = Ecto.UUID.generate()

      event =
        IntegrationEvent.new(
          :enrollment_created,
          :enrollment,
          :enrollment,
          enrollment_id,
          %{
            enrollment_id: enrollment_id,
            child_id: Ecto.UUID.generate(),
            parent_id: Ecto.UUID.generate(),
            parent_user_id: Ecto.UUID.generate(),
            program_id: Ecto.UUID.generate(),
            status: "confirmed"
          }
        )

      assert :ok = EnrolledChildren.project(event)

      # Projecting is not a message to this process, so its bootstrap state is untouched.
      assert %{bootstrapped: true, retry_count: 0} = :sys.get_state(pid)
    end
  end

  # Helper to create users with specific names
  defp user_fixture(attrs) do
    KlassHero.AccountsFixtures.user_fixture(attrs)
  end
end
