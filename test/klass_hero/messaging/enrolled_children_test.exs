defmodule KlassHero.Messaging.EnrolledChildrenTest do
  use KlassHero.DataCase, async: false

  import Ecto.Query
  import ExUnit.CaptureLog
  import KlassHero.EventTestHelper, only: [through_outbox: 1]
  import KlassHero.Factory

  alias KlassHero.Messaging.ConversationSummary
  alias KlassHero.Messaging.EnrolledChild
  alias KlassHero.Messaging.EnrolledChildren
  alias KlassHero.Messaging.Events
  alias KlassHero.Repo
  alias KlassHero.Shared.Domain.Events.Event

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
        from(e in EnrolledChild,
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
        from(e in EnrolledChild, where: e.parent_user_id == ^user.id)
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
        Event.new(
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
          from(e in EnrolledChild,
            where: e.parent_user_id == ^user.id and e.program_id == ^program.id
          )
        )

      assert %EnrolledChild{} = row
      assert row.child_id == child.id
      assert row.child_first_name == "Emma"
    end

    test "re-derivation stamps the names onto that parent's direct conversation summaries" do
      # re_derive_and_emit/2 selects the summaries to stamp by conversation_type, and
      # nothing asserted that hop before #1327 — the three callers all stopped at the
      # messaging_enrolled_children rows.
      user = user_fixture(name: "Sarah Johnson")
      parent = insert(:parent_profile_schema, identity_id: user.id)
      child = insert(:child_schema, first_name: "Emma", last_name: "Johnson")
      insert(:child_guardian_schema, child_id: child.id, guardian_id: parent.id)
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)

      direct_id = Ecto.UUID.generate()
      broadcast_id = Ecto.UUID.generate()

      for {conversation_id, type} <- [{direct_id, :direct}, {broadcast_id, :program_broadcast}] do
        insert(:conversation_summary_schema,
          conversation_id: conversation_id,
          user_id: user.id,
          program_id: program.id,
          conversation_type: type,
          enrolled_child_names: []
        )
      end

      enrollment_id = Ecto.UUID.generate()

      Event.new(:enrollment_created, :enrollment, :enrollment, enrollment_id, %{
        enrollment_id: enrollment_id,
        child_id: child.id,
        parent_id: parent.id,
        parent_user_id: user.id,
        program_id: program.id,
        status: "confirmed"
      })
      |> EnrolledChildren.project()

      assert names_for(direct_id) == ["Emma"]

      assert names_for(broadcast_id) == [],
             "broadcasts carry :program_name, not per-parent child names"
    end

    test "inserts row with nil child_first_name and logs warning when child row is missing" do
      user = user_fixture(name: "Unknown Parent")
      parent = insert(:parent_profile_schema, identity_id: user.id)
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)

      missing_child_id = Ecto.UUID.generate()
      enrollment_id = Ecto.UUID.generate()

      event =
        Event.new(
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
          from(e in EnrolledChild,
            where: e.parent_user_id == ^user.id and e.program_id == ^program.id
          )
        )

      assert %EnrolledChild{} = row
      assert row.child_first_name == nil
    end
  end

  # `project_conversation_created/1` had no test at all before #1327, and it branches on
  # the payload's `:type` — the one field that changed form when atoms started surviving
  # the outbox (#1317). Crossing the real serializer is the point: an in-memory %Event{}
  # would not prove the branch still fires.
  @conversation_type_cases [
    {:direct, ["Emma"]},
    {:program_broadcast, []}
  ]

  describe "handle conversation_created event" do
    for {type, expected_names} <- @conversation_type_cases do
      test "#{type} conversation stamps enrolled_child_names as #{inspect(expected_names)}" do
        type = unquote(type)
        expected_names = unquote(expected_names)

        user = user_fixture(name: "Sarah Johnson")
        provider = insert(:provider_profile_schema)
        program = insert(:program_schema, provider_id: provider.id)
        conversation_id = Ecto.UUID.generate()

        Repo.insert!(%EnrolledChild{
          parent_user_id: user.id,
          program_id: program.id,
          child_id: Ecto.UUID.generate(),
          child_first_name: "Emma"
        })

        insert(:conversation_summary_schema,
          conversation_id: conversation_id,
          user_id: user.id,
          program_id: program.id,
          enrolled_child_names: []
        )

        Events.conversation_created(
          conversation_id,
          type,
          provider.id,
          [user.id],
          program.id
        )
        |> through_outbox()
        |> EnrolledChildren.project()

        assert names_for(conversation_id) == expected_names,
               "#{inspect(type)} took the wrong branch in project_conversation_created/1"
      end
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
        Event.new(
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

  defp names_for(conversation_id) do
    Repo.one!(
      from(s in ConversationSummary,
        where: s.conversation_id == ^conversation_id,
        select: s.enrolled_child_names
      )
    )
  end
end
