defmodule KlassHero.ProgramCatalog.Adapters.Driving.Events.EnrollmentEventHandlerTest do
  use ExUnit.Case, async: true

  alias KlassHero.ProgramCatalog.Adapters.Driving.Events.EnrollmentEventHandler
  alias KlassHero.Shared.Domain.Events.Event

  describe "subscribed_events/0" do
    test "subscribes to participant_policy_set" do
      assert :participant_policy_set in EnrollmentEventHandler.subscribed_events()
    end
  end

  describe "handle_event/1" do
    test "acknowledges participant_policy_set event with :ok" do
      event =
        Event.new(
          :participant_policy_set,
          :enrollment,
          :participant_policy,
          Ecto.UUID.generate(),
          %{program_id: Ecto.UUID.generate()}
        )

      assert :ok = EnrollmentEventHandler.handle_event(event)
    end

    test "ignores unknown events" do
      event =
        Event.new(
          :unknown_event,
          :enrollment,
          :participant_policy,
          Ecto.UUID.generate(),
          %{}
        )

      assert :ignore = EnrollmentEventHandler.handle_event(event)
    end
  end
end
