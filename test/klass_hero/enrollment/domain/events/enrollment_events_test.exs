defmodule KlassHero.Enrollment.Domain.Events.EnrollmentEventsTest do
  @moduledoc "Tests for the EnrollmentEvents factory module."

  use ExUnit.Case, async: true

  alias KlassHero.Enrollment.Domain.Events.EnrollmentEvents, as: Events
  alias KlassHero.Shared.Domain.Events.DomainEvent

  # The id+payload factories share one contract: build a domain event with the
  # right type/aggregate, let the base payload's id win over a caller-supplied id,
  # and raise on a blank id. The table drives that shape; per-factory payload
  # passthrough is covered below, and the multi-arg factories
  # (bulk_invites_imported, invite_resend_requested) keep their own describes.
  @factories [
    %{fun: :participant_policy_set, id: :program_id},
    %{fun: :enrollment_cancelled, id: :enrollment_id},
    %{fun: :enrollment_confirmed, id: :enrollment_id},
    %{fun: :enrollment_created, id: :enrollment_id}
  ]

  for %{fun: fun, id: id} <- @factories do
    describe "#{fun}/3" do
      @fun fun
      @id id

      test "builds a domain event with the right type and aggregate" do
        event = apply(Events, @fun, ["id-1"])

        assert %DomainEvent{} = event
        assert event.event_type == @fun
        assert event.aggregate_id == "id-1"
        assert event.aggregate_type == :enrollment
      end

      test "base payload id wins over caller-supplied and preserves extras" do
        payload = %{@id => "overridden", :extra => "data"}
        event = apply(Events, @fun, ["real-id", payload])

        assert Map.get(event.payload, @id) == "real-id"
        assert event.payload.extra == "data"
      end

      test "raises for a nil or blank id" do
        for bad_id <- [nil, ""] do
          assert_raise ArgumentError, ~r/requires a non-empty #{@id} string/, fn ->
            apply(Events, @fun, [bad_id])
          end
        end
      end
    end
  end

  describe "payload passthrough" do
    test "enrollment_cancelled carries admin_id and reason" do
      event =
        Events.enrollment_cancelled("enr-1", %{
          program_id: "prog-1",
          admin_id: "admin-1",
          reason: "Duplicate booking"
        })

      assert event.payload.admin_id == "admin-1"
      assert event.payload.reason == "Duplicate booking"
    end

    test "enrollment_created carries child_id, parent_user_id, and program_id" do
      event =
        Events.enrollment_created("enr-1", %{
          child_id: "child-1",
          parent_id: "parent-1",
          parent_user_id: "puser-1",
          program_id: "prog-1",
          status: :pending
        })

      assert event.payload.child_id == "child-1"
      assert event.payload.parent_user_id == "puser-1"
      assert event.payload.program_id == "prog-1"
    end

    test "enrollment_confirmed carries the canonical payload" do
      confirmed_at = ~U[2026-01-01 12:00:00Z]

      assert %DomainEvent{
               event_type: :enrollment_confirmed,
               aggregate_id: "enr-1",
               aggregate_type: :enrollment,
               payload: %{
                 enrollment_id: "enr-1",
                 program_id: "prog-1",
                 child_id: "child-1",
                 parent_id: "parent-1",
                 confirmed_at: ^confirmed_at
               }
             } =
               Events.enrollment_confirmed("enr-1", %{
                 program_id: "prog-1",
                 child_id: "child-1",
                 parent_id: "parent-1",
                 confirmed_at: confirmed_at
               })
    end
  end

  describe "bulk_invites_imported/3" do
    test "creates event with correct type and payload" do
      event = Events.bulk_invites_imported("provider-1", ["prog-1", "prog-2"], 5)

      assert %DomainEvent{} = event
      assert event.event_type == :bulk_invites_imported
      assert event.aggregate_type == :enrollment
      assert event.aggregate_id == "provider-1"
      assert event.payload.provider_id == "provider-1"
      assert event.payload.program_ids == ["prog-1", "prog-2"]
      assert event.payload.count == 5
    end

    test "forwards opts to DomainEvent.new/5" do
      correlation_id = Ecto.UUID.generate()

      event = Events.bulk_invites_imported("provider-1", ["prog-1"], 3, correlation_id: correlation_id)

      assert DomainEvent.correlation_id(event) == correlation_id
    end

    test "raises for a nil or empty provider_id" do
      for bad_id <- [nil, ""] do
        assert_raise ArgumentError, ~r/requires a non-empty provider_id string/, fn ->
          Events.bulk_invites_imported(bad_id, ["prog-1"], 1)
        end
      end
    end

    test "raises for non-list program_ids or non-integer count" do
      assert_raise ArgumentError, ~r/requires a non-empty provider_id string/, fn ->
        Events.bulk_invites_imported("provider-1", "not-a-list", 1)
      end

      assert_raise ArgumentError, ~r/requires a non-empty provider_id string/, fn ->
        Events.bulk_invites_imported("provider-1", ["prog-1"], "5")
      end
    end
  end

  describe "invite_resend_requested/4" do
    test "creates event with correct type and payload" do
      provider_id = Ecto.UUID.generate()
      invite_id = Ecto.UUID.generate()
      program_id = Ecto.UUID.generate()

      event = Events.invite_resend_requested(provider_id, invite_id, program_id)

      assert %DomainEvent{} = event
      assert event.event_type == :invite_resend_requested
      assert event.aggregate_type == :enrollment
      assert event.aggregate_id == invite_id
      assert event.payload.provider_id == provider_id
      assert event.payload.invite_id == invite_id
      assert event.payload.program_id == program_id
    end

    test "forwards opts to DomainEvent.new/5" do
      correlation_id = Ecto.UUID.generate()

      event =
        Events.invite_resend_requested(
          Ecto.UUID.generate(),
          Ecto.UUID.generate(),
          Ecto.UUID.generate(),
          correlation_id: correlation_id
        )

      assert DomainEvent.correlation_id(event) == correlation_id
    end

    test "raises when any of provider_id, invite_id, or program_id is blank" do
      valid = Ecto.UUID.generate()

      for args <- [["", valid, valid], [valid, "", valid], [valid, valid, ""]] do
        assert_raise ArgumentError, ~r/invite_resend_requested/, fn ->
          apply(Events, :invite_resend_requested, args)
        end
      end
    end
  end
end
