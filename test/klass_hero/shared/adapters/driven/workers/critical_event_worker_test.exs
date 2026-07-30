defmodule KlassHero.Shared.Adapters.Driven.Workers.CriticalEventWorkerTest do
  use KlassHero.DataCase, async: true

  import ExUnit.CaptureLog

  alias KlassHero.Shared.Adapters.Driven.Events.CriticalEventSerializer
  alias KlassHero.Shared.Adapters.Driven.Persistence.Schemas.ProcessedEvent
  alias KlassHero.Shared.Adapters.Driven.Workers.CriticalEventWorker
  alias KlassHero.Shared.CriticalEventDispatcher
  alias KlassHero.Shared.Domain.Events.Event

  describe "perform/1 with domain events" do
    test "deserializes event and dispatches via CriticalEventDispatcher" do
      event = Event.new(:test_handled, :test_context, :test_aggregate, "agg-1", %{data: "value"})

      args =
        CriticalEventSerializer.serialize(event)
        |> Map.merge(%{
          "handler" => "Elixir.KlassHero.Shared.Adapters.Driven.Workers.CriticalEventWorkerTest.SuccessHandler:handle",
          "context" => "Elixir.KlassHero.TestContext"
        })

      job = %Oban.Job{args: args, attempt: 1, max_attempts: 3}
      assert :ok = CriticalEventWorker.perform(job)

      # Verify processed_events row was created
      ref =
        CriticalEventDispatcher.handler_ref(
          {KlassHero.Shared.Adapters.Driven.Workers.CriticalEventWorkerTest.SuccessHandler, :handle}
        )

      assert Repo.get_by(
               ProcessedEvent,
               event_id: event.event_id,
               handler_ref: ref
             )
    end

    test "returns error when handler fails (triggers Oban retry)" do
      event = Event.new(:test_failed, :test_context, :test_aggregate, "agg-1", %{})

      args =
        CriticalEventSerializer.serialize(event)
        |> Map.merge(%{
          "handler" => "Elixir.KlassHero.Shared.Adapters.Driven.Workers.CriticalEventWorkerTest.FailHandler:handle",
          "context" => "Elixir.KlassHero.TestContext"
        })

      job = %Oban.Job{args: args, attempt: 1, max_attempts: 3}
      assert {:error, :handler_broke} = CriticalEventWorker.perform(job)
    end
  end

  describe "perform/1 with integration events" do
    test "deserializes integration event and dispatches" do
      event =
        Event.new(:test_integration, :test_context, :entity, "ent-1", %{val: 1})

      args =
        CriticalEventSerializer.serialize(event)
        |> Map.put(
          "handler",
          "Elixir.KlassHero.Shared.Adapters.Driven.Workers.CriticalEventWorkerTest.SuccessHandler:handle"
        )

      job = %Oban.Job{args: args, attempt: 1, max_attempts: 3}
      assert :ok = CriticalEventWorker.perform(job)
    end
  end

  describe "retry envelope" do
    # Lifeline only rescues an orphan while `attempt < max_attempts`; at or past the ceiling it
    # discards instead. So this number is not just "how many retries" — it is how long a job orphaned
    # by a vanishing machine remains rescuable at all.
    test "retries long enough for Lifeline to rescue a late orphan" do
      assert %{max_attempts: 10} = CriticalEventWorker.new(%{}).changes
    end
  end

  describe "perform/1 retry logging" do
    test "logs warning on non-final failure" do
      event = Event.new(:test_warn, :test_context, :test_aggregate, "agg-1", %{})

      args =
        CriticalEventSerializer.serialize(event)
        |> Map.merge(%{
          "handler" => "Elixir.KlassHero.Shared.Adapters.Driven.Workers.CriticalEventWorkerTest.FailHandler:handle",
          "context" => "Elixir.KlassHero.TestContext"
        })

      job = %Oban.Job{args: args, attempt: 1, max_attempts: 3}

      log =
        capture_log([level: :warning], fn ->
          CriticalEventWorker.perform(job)
        end)

      assert log =~ "Critical event handler failed (attempt 1/3)"
      assert log =~ "handler_broke"
    end

    test "logs error on permanent failure (final attempt)" do
      event = Event.new(:test_perm_fail, :test_context, :test_aggregate, "agg-1", %{})

      args =
        CriticalEventSerializer.serialize(event)
        |> Map.merge(%{
          "handler" => "Elixir.KlassHero.Shared.Adapters.Driven.Workers.CriticalEventWorkerTest.FailHandler:handle",
          "context" => "Elixir.KlassHero.TestContext"
        })

      job = %Oban.Job{args: args, attempt: 3, max_attempts: 3}

      log =
        capture_log([level: :error], fn ->
          CriticalEventWorker.perform(job)
        end)

      assert log =~ "Critical event permanently failed after 3 attempts"
      assert log =~ "handler_broke"
    end
  end

  # Test handler modules
  defmodule SuccessHandler do
    def handle(_event), do: :ok
  end

  defmodule FailHandler do
    def handle(_event), do: {:error, :handler_broke}
  end
end
