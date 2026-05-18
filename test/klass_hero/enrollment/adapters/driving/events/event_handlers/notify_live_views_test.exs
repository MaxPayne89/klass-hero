defmodule KlassHero.Enrollment.Adapters.Driving.Events.EventHandlers.NotifyLiveViewsTest do
  use ExUnit.Case, async: true

  import KlassHero.EventTestHelper

  alias KlassHero.Enrollment.Adapters.Driving.Events.EventHandlers.NotifyLiveViews
  alias KlassHero.Shared.Domain.Events.DomainEvent

  setup do
    setup_test_events()
    :ok
  end

  describe "handle/1" do
    test "delegates to shared handler and publishes event" do
      program_id = Ecto.UUID.generate()

      event =
        DomainEvent.new(:participant_policy_set, program_id, :enrollment, %{
          program_id: program_id
        })

      assert :ok = NotifyLiveViews.handle(event)
      assert_event_published(:participant_policy_set)
    end
  end

  describe "derive_topic/1" do
    test "falls back to shared derivation when payload omits provider_id" do
      event = DomainEvent.new(:participant_policy_set, "id", :enrollment, %{})
      assert NotifyLiveViews.derive_topic(event) == "enrollment:participant_policy_set"
    end

    test "appends provider scope when payload carries provider_id" do
      provider_id = Ecto.UUID.generate()

      event =
        DomainEvent.new(:enrollment_confirmed, Ecto.UUID.generate(), :enrollment, %{
          provider_id: provider_id
        })

      assert NotifyLiveViews.derive_topic(event) ==
               "enrollment:enrollment_confirmed:provider:#{provider_id}"
    end

    test "does not provider-scope non-enrollment_confirmed events even when payload has provider_id" do
      provider_id = Ecto.UUID.generate()

      event =
        DomainEvent.new(:invite_deleted, Ecto.UUID.generate(), :invite, %{
          provider_id: provider_id,
          invite_id: "some-id"
        })

      assert NotifyLiveViews.derive_topic(event) == "invite:invite_deleted"
    end
  end
end
