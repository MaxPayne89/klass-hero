defmodule KlassHero.Shared.Adapters.Driven.Workers.EventDeliveryWorkerTest do
  use KlassHero.DataCase, async: false

  import ExUnit.CaptureLog

  alias KlassHero.Shared.Adapters.Driven.Events.CriticalEventSerializer
  alias KlassHero.Shared.Adapters.Driven.Persistence.Schemas.ProcessedEvent
  alias KlassHero.Shared.Adapters.Driven.Workers.EventDeliveryWorker
  alias KlassHero.Shared.CriticalEventDispatcher
  alias KlassHero.Shared.Domain.Events.Event

  @topic "integration:test_context:thing_happened"

  defmodule Recorder do
    @moduledoc false

    def calls, do: Agent.get(__MODULE__, &Enum.reverse/1)
    defp record(entry), do: Agent.update(__MODULE__, &[entry | &1])

    def first(%Event{} = event), do: record({:first, event.entity_id})
    def second(%Event{} = event), do: record({:second, event.entity_id})

    def flaky(%Event{} = event) do
      record({:flaky, event.entity_id})
      {:error, :not_today}
    end
  end

  setup do
    start_supervised!(%{id: Recorder, start: {Agent, :start_link, [fn -> [] end, [name: Recorder]]}})

    original = Application.get_env(:klass_hero, :event_consumers)
    on_exit(fn -> Application.put_env(:klass_hero, :event_consumers, original) end)

    {:ok, original: original}
  end

  defp route(consumers, %{original: original}) do
    Application.put_env(:klass_hero, :event_consumers, Map.put(original, @topic, consumers))
  end

  defp event(entity_id) do
    Event.new(:thing_happened, :test_context, :thing, entity_id, %{})
  end

  defp job(events, attempt \\ 1) do
    %Oban.Job{
      args: %{"events" => Enum.map(events, &CriticalEventSerializer.serialize/1)},
      attempt: attempt,
      max_attempts: 10
    }
  end

  test "delivers each event to every consumer of its topic", ctx do
    route([{Recorder, :first}, {Recorder, :second}], ctx)

    assert :ok = EventDeliveryWorker.perform(job([event("thing-1")]))

    assert [{:first, "thing-1"}, {:second, "thing-1"}] = Recorder.calls()
  end

  test "delivers a job's events in the order they were staged", ctx do
    route([{Recorder, :first}], ctx)

    assert :ok = EventDeliveryWorker.perform(job([event("a"), event("b"), event("c")]))

    assert [{:first, "a"}, {:first, "b"}, {:first, "c"}] = Recorder.calls()
  end

  test "records each delivery so a retry does not run it again", ctx do
    route([{Recorder, :first}], ctx)
    event = event("thing-1")

    assert :ok = EventDeliveryWorker.perform(job([event]))
    assert :ok = EventDeliveryWorker.perform(job([event], 2))

    assert [{:first, "thing-1"}] = Recorder.calls()

    assert Repo.get_by(ProcessedEvent,
             event_id: event.event_id,
             handler_ref: CriticalEventDispatcher.handler_ref({Recorder, :first})
           )
  end

  describe "when a consumer fails" do
    test "returns an error so Oban retries the job", ctx do
      route([{Recorder, :flaky}], ctx)

      assert capture_log(fn ->
               assert {:error, :not_today} = EventDeliveryWorker.perform(job([event("thing-1")]))
             end) =~ "Event delivery failed (attempt 1/10)"
    end

    test "still delivers to the consumers after it", ctx do
      route([{Recorder, :flaky}, {Recorder, :second}], ctx)

      capture_log(fn ->
        assert {:error, :not_today} = EventDeliveryWorker.perform(job([event("thing-1")]))
      end)

      assert [{:flaky, "thing-1"}, {:second, "thing-1"}] = Recorder.calls()
    end

    # One poisoned event must not strand the rest of its transaction's events.
    test "still delivers the events after it", ctx do
      route([{Recorder, :flaky}], ctx)

      capture_log(fn ->
        assert {:error, :not_today} = EventDeliveryWorker.perform(job([event("a"), event("b")]))
      end)

      assert [{:flaky, "a"}, {:flaky, "b"}] = Recorder.calls()
    end

    # Error level is what ErrorTracker alerts on, so it must wait for the last attempt.
    test "logs at error level only once retries are exhausted", ctx do
      route([{Recorder, :flaky}], ctx)

      log =
        capture_log(fn ->
          assert {:error, :not_today} = EventDeliveryWorker.perform(job([event("thing-1")], 10))
        end)

      assert log =~ "permanently failed after 10 attempts"
    end
  end

  test "a topic with no consumers is delivered to nobody and succeeds", ctx do
    route([], ctx)

    assert :ok = EventDeliveryWorker.perform(job([event("thing-1")]))
    assert [] = Recorder.calls()
  end
end
