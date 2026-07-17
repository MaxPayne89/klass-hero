defmodule KlassHero.Participation.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEventsTest do
  use ExUnit.Case, async: true

  import KlassHero.EventTestHelper

  alias KlassHero.Participation.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents
  alias KlassHero.Shared.Adapters.Driven.Events.TestIntegrationEventPublisher
  alias KlassHero.Shared.Domain.Events.DomainEvent

  setup do
    setup_test_integration_events()
    :ok
  end

  # ---------------------------------------------------------------------------
  # Session events (aggregate_type: :participation)
  # ---------------------------------------------------------------------------

  describe "handle/1 — :session_created" do
    test "promotes to session_created integration event" do
      session_id = Ecto.UUID.generate()
      program_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:session_created, session_id, :participation, %{
          session_id: session_id,
          program_id: program_id,
          session_date: ~D[2026-04-01],
          start_time: ~T[09:00:00],
          end_time: ~T[10:00:00],
          location: "Room A",
          max_capacity: 20
        })

      assert :ok = PromoteIntegrationEvents.handle(domain_event)

      event = assert_integration_event_published(:session_created)
      assert event.entity_id == session_id
      assert event.source_context == :participation
    end

    test "swallows publish failures with :ok" do
      session_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:session_created, session_id, :participation, %{
          session_id: session_id,
          program_id: Ecto.UUID.generate(),
          session_date: ~D[2026-04-01],
          start_time: ~T[09:00:00],
          end_time: ~T[10:00:00],
          location: "Room A",
          max_capacity: 20
        })

      TestIntegrationEventPublisher.configure_publish_error(:pubsub_down)

      assert :ok = PromoteIntegrationEvents.handle(domain_event)
      assert_no_integration_events_published()
    end
  end

  describe "handle/1 — :session_started" do
    test "promotes to session_started integration event" do
      session_id = Ecto.UUID.generate()
      program_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:session_started, session_id, :participation, %{
          session_id: session_id,
          program_id: program_id,
          started_at: DateTime.utc_now()
        })

      assert :ok = PromoteIntegrationEvents.handle(domain_event)

      event = assert_integration_event_published(:session_started)
      assert event.entity_id == session_id
      assert event.source_context == :participation
    end

    test "swallows publish failures with :ok" do
      session_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:session_started, session_id, :participation, %{
          session_id: session_id,
          program_id: Ecto.UUID.generate(),
          started_at: DateTime.utc_now()
        })

      TestIntegrationEventPublisher.configure_publish_error(:pubsub_down)

      assert :ok = PromoteIntegrationEvents.handle(domain_event)
      assert_no_integration_events_published()
    end
  end

  describe "handle/1 — :session_completed" do
    test "promotes to session_completed integration event" do
      session_id = Ecto.UUID.generate()
      program_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:session_completed, session_id, :participation, %{
          session_id: session_id,
          program_id: program_id,
          provider_id: provider_id,
          program_title: "Art Class",
          completed_at: DateTime.utc_now()
        })

      assert :ok = PromoteIntegrationEvents.handle(domain_event)

      event = assert_integration_event_published(:session_completed)
      assert event.entity_id == session_id
      assert event.source_context == :participation
    end

    test "swallows publish failures with :ok" do
      session_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:session_completed, session_id, :participation, %{
          session_id: session_id,
          program_id: Ecto.UUID.generate(),
          provider_id: Ecto.UUID.generate(),
          program_title: "Art Class",
          completed_at: DateTime.utc_now()
        })

      TestIntegrationEventPublisher.configure_publish_error(:pubsub_down)

      assert :ok = PromoteIntegrationEvents.handle(domain_event)
      assert_no_integration_events_published()
    end
  end

  describe "handle/1 — :session_cancelled" do
    test "promotes to session_cancelled integration event" do
      session_id = Ecto.UUID.generate()
      program_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:session_cancelled, session_id, :participation, %{
          session_id: session_id,
          program_id: program_id,
          cancelled_at: DateTime.utc_now()
        })

      assert :ok = PromoteIntegrationEvents.handle(domain_event)

      event = assert_integration_event_published(:session_cancelled)
      assert event.entity_id == session_id
      assert event.source_context == :participation
      assert event.payload.program_id == program_id
    end

    test "swallows publish failures with :ok" do
      session_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:session_cancelled, session_id, :participation, %{
          session_id: session_id,
          program_id: Ecto.UUID.generate(),
          cancelled_at: DateTime.utc_now()
        })

      TestIntegrationEventPublisher.configure_publish_error(:pubsub_down)

      assert :ok = PromoteIntegrationEvents.handle(domain_event)
      assert_no_integration_events_published()
    end
  end

  # ---------------------------------------------------------------------------
  # Check-in/out events (aggregate_type: :participation)
  # ---------------------------------------------------------------------------

  describe "handle/1 — :child_checked_in" do
    test "promotes to child_checked_in integration event" do
      record_id = Ecto.UUID.generate()
      session_id = Ecto.UUID.generate()
      child_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:child_checked_in, record_id, :participation, %{
          record_id: record_id,
          session_id: session_id,
          child_id: child_id,
          checked_in_by: Ecto.UUID.generate(),
          checked_in_at: DateTime.utc_now(),
          notes: "Arrived on time"
        })

      assert :ok = PromoteIntegrationEvents.handle(domain_event)

      event = assert_integration_event_published(:child_checked_in)
      assert event.entity_id == record_id
      assert event.source_context == :participation
    end

    test "swallows publish failures with :ok" do
      record_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:child_checked_in, record_id, :participation, %{
          record_id: record_id,
          session_id: Ecto.UUID.generate(),
          child_id: Ecto.UUID.generate(),
          checked_in_by: Ecto.UUID.generate(),
          checked_in_at: DateTime.utc_now(),
          notes: nil
        })

      TestIntegrationEventPublisher.configure_publish_error(:pubsub_down)

      assert :ok = PromoteIntegrationEvents.handle(domain_event)
      assert_no_integration_events_published()
    end
  end

  describe "handle/1 — :child_checked_out" do
    test "promotes to child_checked_out integration event" do
      record_id = Ecto.UUID.generate()
      session_id = Ecto.UUID.generate()
      child_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:child_checked_out, record_id, :participation, %{
          record_id: record_id,
          session_id: session_id,
          child_id: child_id,
          checked_out_by: Ecto.UUID.generate(),
          checked_out_at: DateTime.utc_now(),
          notes: "Picked up by parent"
        })

      assert :ok = PromoteIntegrationEvents.handle(domain_event)

      event = assert_integration_event_published(:child_checked_out)
      assert event.entity_id == record_id
      assert event.source_context == :participation
    end

    test "swallows publish failures with :ok" do
      record_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:child_checked_out, record_id, :participation, %{
          record_id: record_id,
          session_id: Ecto.UUID.generate(),
          child_id: Ecto.UUID.generate(),
          checked_out_by: Ecto.UUID.generate(),
          checked_out_at: DateTime.utc_now(),
          notes: nil
        })

      TestIntegrationEventPublisher.configure_publish_error(:pubsub_down)

      assert :ok = PromoteIntegrationEvents.handle(domain_event)
      assert_no_integration_events_published()
    end
  end

  describe "handle/1 — :child_marked_absent" do
    test "promotes to child_marked_absent integration event" do
      record_id = Ecto.UUID.generate()
      session_id = Ecto.UUID.generate()
      child_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:child_marked_absent, record_id, :participation, %{
          record_id: record_id,
          session_id: session_id,
          child_id: child_id
        })

      assert :ok = PromoteIntegrationEvents.handle(domain_event)

      event = assert_integration_event_published(:child_marked_absent)
      assert event.entity_id == record_id
      assert event.source_context == :participation
    end

    test "swallows publish failures with :ok" do
      record_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:child_marked_absent, record_id, :participation, %{
          record_id: record_id,
          session_id: Ecto.UUID.generate(),
          child_id: Ecto.UUID.generate()
        })

      TestIntegrationEventPublisher.configure_publish_error(:pubsub_down)

      assert :ok = PromoteIntegrationEvents.handle(domain_event)
      assert_no_integration_events_published()
    end
  end

  # ---------------------------------------------------------------------------
  # Session note events (aggregate_type: :session_note)
  # ---------------------------------------------------------------------------

  describe "handle/1 — :session_note_submitted" do
    test "promotes to session_note_submitted integration event" do
      note_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:session_note_submitted, note_id, :session_note, %{
          note_id: note_id,
          participation_record_id: Ecto.UUID.generate(),
          child_id: Ecto.UUID.generate(),
          provider_id: Ecto.UUID.generate(),
          parent_id: Ecto.UUID.generate()
        })

      assert :ok = PromoteIntegrationEvents.handle(domain_event)

      event = assert_integration_event_published(:session_note_submitted)
      assert event.entity_id == note_id
      assert event.source_context == :participation
    end

    test "swallows publish failures with :ok" do
      note_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:session_note_submitted, note_id, :session_note, %{
          note_id: note_id,
          participation_record_id: Ecto.UUID.generate(),
          child_id: Ecto.UUID.generate(),
          provider_id: Ecto.UUID.generate(),
          parent_id: nil
        })

      TestIntegrationEventPublisher.configure_publish_error(:pubsub_down)

      assert :ok = PromoteIntegrationEvents.handle(domain_event)
      assert_no_integration_events_published()
    end
  end

  describe "handle/1 — :session_note_approved" do
    test "promotes to session_note_approved integration event" do
      note_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:session_note_approved, note_id, :session_note, %{
          note_id: note_id,
          participation_record_id: Ecto.UUID.generate(),
          child_id: Ecto.UUID.generate(),
          provider_id: Ecto.UUID.generate(),
          parent_id: Ecto.UUID.generate()
        })

      assert :ok = PromoteIntegrationEvents.handle(domain_event)

      event = assert_integration_event_published(:session_note_approved)
      assert event.entity_id == note_id
      assert event.source_context == :participation
    end

    test "swallows publish failures with :ok" do
      note_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:session_note_approved, note_id, :session_note, %{
          note_id: note_id,
          participation_record_id: Ecto.UUID.generate(),
          child_id: Ecto.UUID.generate(),
          provider_id: Ecto.UUID.generate(),
          parent_id: nil
        })

      TestIntegrationEventPublisher.configure_publish_error(:pubsub_down)

      assert :ok = PromoteIntegrationEvents.handle(domain_event)
      assert_no_integration_events_published()
    end
  end

  describe "handle/1 -- :roster_seeded" do
    test "promotes to roster_seeded integration event" do
      session_id = Ecto.UUID.generate()
      program_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:roster_seeded, session_id, :participation, %{
          session_id: session_id,
          program_id: program_id,
          seeded_count: 3
        })

      assert :ok = PromoteIntegrationEvents.handle(domain_event)

      event = assert_integration_event_published(:roster_seeded)
      assert event.entity_id == session_id
      assert event.source_context == :participation
    end

    test "swallows publish failures with :ok" do
      session_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:roster_seeded, session_id, :participation, %{
          session_id: session_id,
          program_id: Ecto.UUID.generate(),
          seeded_count: 3
        })

      TestIntegrationEventPublisher.configure_publish_error(:pubsub_down)

      assert :ok = PromoteIntegrationEvents.handle(domain_event)
      assert_no_integration_events_published()
    end
  end

  describe "handle/1 — :session_note_rejected" do
    test "promotes to session_note_rejected integration event" do
      note_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:session_note_rejected, note_id, :session_note, %{
          note_id: note_id,
          participation_record_id: Ecto.UUID.generate(),
          child_id: Ecto.UUID.generate(),
          provider_id: Ecto.UUID.generate(),
          parent_id: Ecto.UUID.generate()
        })

      assert :ok = PromoteIntegrationEvents.handle(domain_event)

      event = assert_integration_event_published(:session_note_rejected)
      assert event.entity_id == note_id
      assert event.source_context == :participation
    end

    test "swallows publish failures with :ok" do
      note_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:session_note_rejected, note_id, :session_note, %{
          note_id: note_id,
          participation_record_id: Ecto.UUID.generate(),
          child_id: Ecto.UUID.generate(),
          provider_id: Ecto.UUID.generate(),
          parent_id: nil
        })

      TestIntegrationEventPublisher.configure_publish_error(:pubsub_down)

      assert :ok = PromoteIntegrationEvents.handle(domain_event)
      assert_no_integration_events_published()
    end
  end
end
