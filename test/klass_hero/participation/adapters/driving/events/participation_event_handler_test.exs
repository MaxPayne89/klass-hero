defmodule KlassHero.Participation.Adapters.Driving.Events.ParticipationEventHandlerTest do
  @moduledoc """
  Tests for ParticipationEventHandler handling of child_data_anonymized integration events.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Participation.Adapters.Driving.Events.ParticipationEventHandler
  alias KlassHero.Participation.SessionNote
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  describe "handle_event/1 for :child_data_anonymized" do
    test "anonymizes all session notes for the child" do
      note =
        insert(:session_note_schema,
          content: "Very attentive today",
          status: :approved
        )

      event =
        IntegrationEvent.new(
          :child_data_anonymized,
          :identity,
          :child,
          note.child_id,
          %{child_id: note.child_id},
          criticality: :critical
        )

      assert :ok == ParticipationEventHandler.handle_event(event)

      reloaded = Repo.get!(SessionNote, note.id)
      assert reloaded.content == "[Removed - account deleted]"
      assert reloaded.status == :rejected
      assert is_nil(reloaded.rejection_reason)
    end

    test "returns :ok when child has no session notes" do
      child_id = Ecto.UUID.generate()

      event =
        IntegrationEvent.new(
          :child_data_anonymized,
          :identity,
          :child,
          child_id,
          %{child_id: child_id},
          criticality: :critical
        )

      assert :ok == ParticipationEventHandler.handle_event(event)
    end
  end

  describe "handle_event/1 for unknown events" do
    test "ignores unrecognized event types" do
      event =
        IntegrationEvent.new(
          :some_unknown_event,
          :unknown,
          :unknown,
          Ecto.UUID.generate(),
          %{}
        )

      assert :ignore == ParticipationEventHandler.handle_event(event)
    end
  end

  describe "subscribed_events/0" do
    test "subscribes to :child_data_anonymized" do
      assert :child_data_anonymized in ParticipationEventHandler.subscribed_events()
    end
  end
end
