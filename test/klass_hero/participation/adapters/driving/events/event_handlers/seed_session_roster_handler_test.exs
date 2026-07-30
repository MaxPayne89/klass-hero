defmodule KlassHero.Participation.Adapters.Driving.Events.EventHandlers.SeedSessionRosterHandlerTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.Participation.Adapters.Driving.Events.EventHandlers.SeedSessionRosterHandler
  alias KlassHero.Shared.Domain.Events.Event

  describe "handle_event/1" do
    test "delegates to SeedSessionRoster for session_created events" do
      program = KlassHero.Factory.insert(:program_schema)

      session =
        KlassHero.Factory.insert(:program_session_schema,
          program_id: program.id,
          status: "scheduled"
        )

      event =
        Event.new(
          :session_created,
          :participation,
          :session,
          session.id,
          %{
            session_id: session.id,
            program_id: program.id,
            session_date: ~D[2026-03-20],
            start_time: ~T[09:00:00],
            end_time: ~T[10:00:00]
          }
        )

      assert :ok = SeedSessionRosterHandler.handle_event(event)
    end

    test "ignores non-session_created events" do
      event =
        Event.new(
          :session_started,
          :participation,
          :session,
          Ecto.UUID.generate(),
          %{session_id: Ecto.UUID.generate(), program_id: Ecto.UUID.generate()}
        )

      assert :ignore = SeedSessionRosterHandler.handle_event(event)
    end
  end

  describe "subscribed_events/0" do
    test "subscribes to session_created" do
      assert :session_created in SeedSessionRosterHandler.subscribed_events()
    end
  end
end
