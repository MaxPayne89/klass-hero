defmodule KlassHero.Enrollment.NotificationsTest do
  use ExUnit.Case, async: true

  alias KlassHero.Enrollment.Notifications

  defp subscribe(topic), do: Phoenix.PubSub.subscribe(KlassHero.PubSub, topic)

  test "a confirmed enrollment reaches only its own provider's topic" do
    provider_id = Ecto.UUID.generate()
    other_provider_id = Ecto.UUID.generate()
    enrollment_id = Ecto.UUID.generate()

    subscribe(Notifications.provider_scoped_topic(:enrollment_confirmed, provider_id))
    subscribe(Notifications.provider_scoped_topic(:enrollment_confirmed, other_provider_id))

    assert :ok = Notifications.enrollment_confirmed(enrollment_id, provider_id)

    assert_receive {:enrollment_confirmed, ^enrollment_id}
    refute_receive {:enrollment_confirmed, _}, 50
  end

  # The program detail page filters client-side, so the message must carry the
  # program it is about — the topic is shared by every program.
  test "a participant policy announces which program it belongs to" do
    program_id = Ecto.UUID.generate()
    subscribe("enrollment:participant_policy_set")

    assert :ok = Notifications.participant_policy_set(program_id)

    assert_receive {:participant_policy_set, ^program_id}
  end
end
