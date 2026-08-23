defmodule KlassHero.Participation.NotificationsTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.Participation.Domain.Events.ParticipationEvents
  alias KlassHero.Participation.Notifications
  alias KlassHero.Shared.Domain.Events.Event

  # Every session-lifecycle event says the same thing to a LiveView — "this session
  # is not what you rendered" — so they collapse to one message rather than nine.
  @session_events [:session_created, :session_started, :session_completed, :session_cancelled, :roster_seeded]

  @attendance_kinds %{
    child_checked_in: :checked_in,
    child_checked_out: :checked_out,
    child_marked_absent: :marked_absent,
    attendance_corrected: :corrected
  }

  @note_events [:session_note_submitted, :session_note_approved, :session_note_rejected]

  defp subscribe(topic), do: Phoenix.PubSub.subscribe(KlassHero.PubSub, topic)

  defp program_of_new_provider do
    provider = KlassHero.Factory.insert(:provider_profile_schema)
    program = KlassHero.Factory.insert(:program_schema, provider_id: provider.id)
    {provider.id, program.id}
  end

  defp event(type, payload) do
    Event.new(type, :participation, ParticipationEvents.entity_type_for(type), Ecto.UUID.generate(), payload)
  end

  describe "session lifecycle" do
    test "each session event tells the provider's topic which session changed" do
      {provider_id, program_id} = program_of_new_provider()
      subscribe("participation:provider:#{provider_id}")

      for type <- @session_events do
        session_id = Ecto.UUID.generate()
        assert :ok = Notifications.notify(event(type, %{session_id: session_id, program_id: program_id}))

        assert_receive {:session_changed, ^session_id},
                       100,
                       "#{type} should announce its session on the provider topic"
      end
    end

    test "a generated batch is keyed on the program, not one session" do
      {provider_id, program_id} = program_of_new_provider()
      subscribe("participation:provider:#{provider_id}")

      assert :ok = Notifications.notify(event(:sessions_generated, %{program_id: program_id, sessions: []}))

      assert_receive {:sessions_generated, ^program_id}
    end
  end

  describe "attendance" do
    test "reaches both the provider and the child topic, carrying the kind" do
      {provider_id, program_id} = program_of_new_provider()
      child_id = Ecto.UUID.generate()
      subscribe("participation:provider:#{provider_id}")
      subscribe("participation:child:#{child_id}")

      for {type, kind} <- @attendance_kinds do
        record_id = Ecto.UUID.generate()
        session_id = Ecto.UUID.generate()

        payload = %{record_id: record_id, session_id: session_id, child_id: child_id, program_id: program_id}
        assert :ok = Notifications.notify(event(type, payload))

        # Once per topic — the provider view patches a session row, the parent view
        # patches a record row, and only the parent view needs `kind`.
        for _topic <- [:provider, :child] do
          assert_receive {:attendance_changed,
                          %{record_id: ^record_id, session_id: ^session_id, child_id: ^child_id, kind: ^kind}},
                         100,
                         "#{type} should announce kind #{kind} on both topics"
        end
      end
    end
  end

  describe "session notes" do
    test "route by the provider_id in the payload, with no program lookup" do
      provider_id = Ecto.UUID.generate()
      child_id = Ecto.UUID.generate()
      subscribe("participation:provider:#{provider_id}")
      subscribe("participation:child:#{child_id}")

      for type <- @note_events do
        assert :ok = Notifications.notify(event(type, %{provider_id: provider_id, child_id: child_id}))

        for _topic <- [:provider, :child] do
          assert_receive :session_notes_changed, 100, "#{type} should notify both topics"
        end
      end
    end
  end

  describe "degradation" do
    test "an unresolvable program still notifies the child topic" do
      child_id = Ecto.UUID.generate()
      subscribe("participation:child:#{child_id}")

      payload = %{
        record_id: Ecto.UUID.generate(),
        session_id: Ecto.UUID.generate(),
        child_id: child_id,
        program_id: Ecto.UUID.generate()
      }

      assert :ok = Notifications.notify(event(:child_checked_in, payload))
      assert_receive {:attendance_changed, %{child_id: ^child_id}}
    end

    test "an event with no program_id and no child_id notifies nobody and still returns :ok" do
      {provider_id, _program_id} = program_of_new_provider()
      subscribe("participation:provider:#{provider_id}")

      assert :ok = Notifications.notify(event(:session_created, %{session_id: Ecto.UUID.generate()}))

      refute_receive {:session_changed, _}, 50
    end
  end

  test "notify_all/1 delivers a transaction's events in the order they were staged" do
    {provider_id, program_id} = program_of_new_provider()
    subscribe("participation:provider:#{provider_id}")

    [first, second] = ids = [Ecto.UUID.generate(), Ecto.UUID.generate()]
    events = for id <- ids, do: event(:session_created, %{session_id: id, program_id: program_id})

    assert :ok = Notifications.notify_all(events)

    assert_receive {:session_changed, ^first}
    assert_receive {:session_changed, ^second}
  end
end
