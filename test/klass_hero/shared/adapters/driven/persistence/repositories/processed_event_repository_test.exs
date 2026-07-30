defmodule KlassHero.Shared.Adapters.Driven.Persistence.Repositories.ProcessedEventRepositoryTest do
  use KlassHero.DataCase, async: true
  use Oban.Testing, repo: KlassHero.Repo

  import ExUnit.CaptureLog

  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.Repositories.ProcessedEventRepository
  alias KlassHero.Shared.Adapters.Driven.Persistence.Schemas.ProcessedEvent
  alias KlassHero.Shared.Domain.Events.Event

  describe "execute_atomically/3" do
    test "runs handler and inserts row on success" do
      event_id = Ecto.UUID.generate()
      handler_ref = "Elixir.TestModule:handle"
      test_pid = self()

      result =
        ProcessedEventRepository.execute_atomically(event_id, handler_ref, fn ->
          send(test_pid, :handler_called)
          :ok
        end)

      assert result == :ok
      assert_received :handler_called
      assert Repo.get_by(ProcessedEvent, event_id: event_id, handler_ref: handler_ref)
    end

    test "skips handler when already processed" do
      event_id = Ecto.UUID.generate()
      handler_ref = "Elixir.TestModule:handle"
      test_pid = self()

      :ok =
        ProcessedEventRepository.execute_atomically(event_id, handler_ref, fn ->
          send(test_pid, :first)
          :ok
        end)

      assert_received :first

      :ok =
        ProcessedEventRepository.execute_atomically(event_id, handler_ref, fn ->
          send(test_pid, :second)
          :ok
        end)

      refute_received :second
    end

    test "rolls back row on handler failure" do
      event_id = Ecto.UUID.generate()
      handler_ref = "Elixir.TestModule:handle"

      result =
        ProcessedEventRepository.execute_atomically(event_id, handler_ref, fn ->
          {:error, :something_broke}
        end)

      assert result == {:error, :something_broke}
      refute Repo.get_by(ProcessedEvent, event_id: event_id, handler_ref: handler_ref)
    end

    test "rolls back on handler crash and logs stacktrace" do
      event_id = Ecto.UUID.generate()
      handler_ref = "Elixir.TestModule:handle"

      log =
        capture_log([level: :error], fn ->
          ProcessedEventRepository.execute_atomically(event_id, handler_ref, fn ->
            raise "kaboom"
          end)
        end)

      assert log =~ "Critical event handler crashed"
      assert log =~ "kaboom"
      refute Repo.get_by(ProcessedEvent, event_id: event_id, handler_ref: handler_ref)
    end

    test "treats :ignore return as success" do
      event_id = Ecto.UUID.generate()
      handler_ref = "Elixir.TestModule:handle"

      result =
        ProcessedEventRepository.execute_atomically(event_id, handler_ref, fn ->
          :ignore
        end)

      assert result == :ok
      assert Repo.get_by(ProcessedEvent, event_id: event_id, handler_ref: handler_ref)
    end
  end

  describe "mark_processed/2" do
    test "inserts row without running a handler" do
      event_id = Ecto.UUID.generate()
      handler_ref = "Elixir.TestModule:handle"

      assert :ok = ProcessedEventRepository.mark_processed(event_id, handler_ref)
      assert Repo.get_by(ProcessedEvent, event_id: event_id, handler_ref: handler_ref)
    end

    test "is idempotent" do
      event_id = Ecto.UUID.generate()
      handler_ref = "Elixir.TestModule:handle"

      assert :ok = ProcessedEventRepository.mark_processed(event_id, handler_ref)
      assert :ok = ProcessedEventRepository.mark_processed(event_id, handler_ref)
    end
  end

  describe "enqueue_durable_retry/2" do
    test "serializes event and inserts Oban job" do
      event = Event.new(:test_retry, :test_context, :test, "agg-1", %{data: "value"})
      handler_ref = "Elixir.TestModule:handle"

      # Trigger: use manual mode so Oban doesn't execute the job immediately
      # Why: inline mode would try to run the worker, which requires a real handler module
      # Outcome: job is inserted but not executed — we verify the enqueue succeeded
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = ProcessedEventRepository.enqueue_durable_retry(event, handler_ref)
      end)
    end
  end
end
