defmodule KlassHero.Enrollment.Domain.Events.EnrollmentEventsTest do
  @moduledoc "Tests for the EnrollmentEvents factory module."

  use ExUnit.Case, async: true

  alias KlassHero.Enrollment.Domain.Events.EnrollmentEvents, as: Events
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  # Every id-and-payload factory shares one contract: build an event with stable
  # identity fields, let the id argument win over any caller-supplied one
  # (preserving extras), and raise on a blank id. The table drives that shape;
  # the two multi-argument factories and enrollment_created's parent_user_id
  # passthrough are kept below it.
  @factories [
    %{fun: :invite_claimed, id: :invite_id, entity: :invite},
    %{fun: :enrollment_cancelled, id: :enrollment_id, entity: :enrollment},
    %{fun: :participant_policy_set, id: :program_id, entity: :participant_policy},
    %{fun: :enrollment_created, id: :enrollment_id, entity: :enrollment}
  ]

  for %{fun: fun, id: id, entity: entity} <- @factories do
    describe "#{fun}/3" do
      @fun fun
      @id id
      @entity entity

      test "builds an event with stable identity fields" do
        event = apply(Events, @fun, ["id-1"])

        assert %IntegrationEvent{} = event
        assert event.event_type == @fun
        assert event.source_context == :enrollment
        assert event.entity_type == @entity
        assert event.entity_id == "id-1"
      end

      test "the id argument wins over a caller-supplied one and preserves extras" do
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

  describe "enrollment_created/3 payload" do
    test "carries parent_user_id through to the integration event" do
      event =
        Events.enrollment_created("enr-1", %{
          child_id: "child-1",
          parent_id: "parent-1",
          parent_user_id: "puser-1",
          program_id: "prog-1",
          status: :pending
        })

      assert event.payload.parent_user_id == "puser-1"
    end
  end

  # These two cross no context boundary — they drive same-context bus handlers —
  # so they take the arguments their producers hold rather than an id + payload.
  describe "bulk_invites_imported/4" do
    test "creates an event with correct type and payload" do
      event = Events.bulk_invites_imported("provider-1", ["prog-1", "prog-2"], 5)

      assert %IntegrationEvent{} = event
      assert event.event_type == :bulk_invites_imported
      assert event.source_context == :enrollment
      assert event.entity_type == :provider
      assert event.entity_id == "provider-1"
      assert event.payload.provider_id == "provider-1"
      assert event.payload.program_ids == ["prog-1", "prog-2"]
      assert event.payload.count == 5
    end

    test "forwards opts to the event" do
      correlation_id = Ecto.UUID.generate()

      event = Events.bulk_invites_imported("provider-1", ["prog-1"], 3, correlation_id: correlation_id)

      assert IntegrationEvent.correlation_id(event) == correlation_id
    end

    test "raises for a blank provider_id, non-list program_ids, or non-integer count" do
      for args <- [
            [nil, ["prog-1"], 1],
            ["", ["prog-1"], 1],
            ["provider-1", "not-a-list", 1],
            ["provider-1", ["prog-1"], "5"]
          ] do
        assert_raise ArgumentError, ~r/requires a non-empty provider_id string/, fn ->
          apply(Events, :bulk_invites_imported, args)
        end
      end
    end
  end

  describe "invite_resend_requested/4" do
    test "creates an event with correct type and payload" do
      provider_id = Ecto.UUID.generate()
      invite_id = Ecto.UUID.generate()
      program_id = Ecto.UUID.generate()

      event = Events.invite_resend_requested(provider_id, invite_id, program_id)

      assert %IntegrationEvent{} = event
      assert event.event_type == :invite_resend_requested
      assert event.source_context == :enrollment
      assert event.entity_type == :invite
      assert event.entity_id == invite_id
      assert event.payload.provider_id == provider_id
      assert event.payload.invite_id == invite_id
      assert event.payload.program_id == program_id
    end

    test "forwards opts to the event" do
      correlation_id = Ecto.UUID.generate()

      event =
        Events.invite_resend_requested(
          Ecto.UUID.generate(),
          Ecto.UUID.generate(),
          Ecto.UUID.generate(),
          correlation_id: correlation_id
        )

      assert IntegrationEvent.correlation_id(event) == correlation_id
    end

    test "raises when any of the three ids is blank" do
      id = Ecto.UUID.generate()

      for args <- [["", id, id], [id, "", id], [id, id, ""]] do
        assert_raise ArgumentError, ~r/requires non-empty provider_id, invite_id, and program_id/, fn ->
          apply(Events, :invite_resend_requested, args)
        end
      end
    end
  end
end
