defmodule KlassHero.Shared.CriticalEventDispatcherTest do
  use KlassHero.DataCase, async: true

  import ExUnit.CaptureLog

  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.Schemas.ProcessedEvent
  alias KlassHero.Shared.CriticalEventDispatcher

  describe "handler_ref/1" do
    test "produces canonical string from {module, function} tuple" do
      ref = CriticalEventDispatcher.handler_ref({MyApp.SomeHandler, :handle_event})
      assert ref == "Elixir.MyApp.SomeHandler:handle_event"
    end

    test "produces different refs for different functions on same module" do
      ref_a = CriticalEventDispatcher.handler_ref({MyApp.Handler, :handle})
      ref_b = CriticalEventDispatcher.handler_ref({MyApp.Handler, :handle_event})
      assert ref_a != ref_b
    end
  end

  describe "execute/3" do
    test "runs handler and inserts processed_events row on success" do
      event_id = Ecto.UUID.generate()
      handler_ref = "Elixir.TestModule:handle"
      test_pid = self()

      result =
        CriticalEventDispatcher.execute(event_id, handler_ref, fn ->
          send(test_pid, :handler_called)
          :ok
        end)

      assert result == :ok
      assert_received :handler_called

      # Verify row exists
      assert Repo.get_by(ProcessedEvent, event_id: event_id, handler_ref: handler_ref)
    end

    test "skips handler and returns :ok when already processed" do
      event_id = Ecto.UUID.generate()
      handler_ref = "Elixir.TestModule:handle"
      test_pid = self()

      # First call processes normally
      :ok =
        CriticalEventDispatcher.execute(event_id, handler_ref, fn ->
          send(test_pid, :first_call)
          :ok
        end)

      assert_received :first_call

      # Second call is idempotent — handler not called
      :ok =
        CriticalEventDispatcher.execute(event_id, handler_ref, fn ->
          send(test_pid, :second_call)
          :ok
        end)

      refute_received :second_call
    end

    test "rolls back processed_events row on handler failure" do
      event_id = Ecto.UUID.generate()
      handler_ref = "Elixir.TestModule:handle"

      result =
        CriticalEventDispatcher.execute(event_id, handler_ref, fn ->
          {:error, :something_went_wrong}
        end)

      assert result == {:error, :something_went_wrong}

      # Row should NOT exist — rolled back
      refute Repo.get_by(ProcessedEvent, event_id: event_id, handler_ref: handler_ref)
    end

    test "rolls back on handler crash and returns error" do
      event_id = Ecto.UUID.generate()
      handler_ref = "Elixir.TestModule:handle"

      result =
        CriticalEventDispatcher.execute(event_id, handler_ref, fn ->
          raise "boom"
        end)

      assert {:error, {:handler_crashed, %RuntimeError{message: "boom"}}} = result

      # Row should NOT exist — rolled back
      refute Repo.get_by(ProcessedEvent, event_id: event_id, handler_ref: handler_ref)
    end

    test "treats :ignore return as success" do
      event_id = Ecto.UUID.generate()
      handler_ref = "Elixir.TestModule:handle"

      result =
        CriticalEventDispatcher.execute(event_id, handler_ref, fn ->
          :ignore
        end)

      assert result == :ok
      assert Repo.get_by(ProcessedEvent, event_id: event_id, handler_ref: handler_ref)
    end

    test "logs crash with stacktrace before rolling back" do
      event_id = Ecto.UUID.generate()
      handler_ref = "Elixir.TestModule:handle"

      log =
        capture_log([level: :error], fn ->
          CriticalEventDispatcher.execute(event_id, handler_ref, fn ->
            raise "kaboom"
          end)
        end)

      assert log =~ "Critical event handler crashed"
      assert log =~ "kaboom"
    end

    test "allows retry after failure (row was rolled back)" do
      event_id = Ecto.UUID.generate()
      handler_ref = "Elixir.TestModule:handle"
      test_pid = self()

      # First attempt fails
      {:error, _} =
        CriticalEventDispatcher.execute(event_id, handler_ref, fn ->
          {:error, :transient}
        end)

      # Retry succeeds — row was not left behind
      :ok =
        CriticalEventDispatcher.execute(event_id, handler_ref, fn ->
          send(test_pid, :retry_succeeded)
          :ok
        end)

      assert_received :retry_succeeded
      assert Repo.get_by(ProcessedEvent, event_id: event_id, handler_ref: handler_ref)
    end
  end

  describe "parse_handler_ref/1" do
    test "round-trips with handler_ref/1" do
      original = {MyApp.SomeHandler, :handle_event}
      ref_str = CriticalEventDispatcher.handler_ref(original)
      assert CriticalEventDispatcher.parse_handler_ref(ref_str) == original
    end

    test "raises ArgumentError on missing colon" do
      assert_raise ArgumentError, ~r/Invalid handler_ref format/, fn ->
        CriticalEventDispatcher.parse_handler_ref("NoColonHere")
      end
    end

    test "raises ArgumentError on multiple colons" do
      assert_raise ArgumentError, ~r/Invalid handler_ref format/, fn ->
        CriticalEventDispatcher.parse_handler_ref("Elixir.Mod:func:extra")
      end
    end

    test "raises ArgumentError on non-existent atom" do
      assert_raise ArgumentError, fn ->
        CriticalEventDispatcher.parse_handler_ref("Elixir.NonExistentModule99999:handle")
      end
    end
  end

  describe "mark_processed/2" do
    test "inserts a processed_events row" do
      event_id = Ecto.UUID.generate()
      handler_ref = "Elixir.TestModule:handle"

      assert :ok = CriticalEventDispatcher.mark_processed(event_id, handler_ref)
      assert Repo.get_by(ProcessedEvent, event_id: event_id, handler_ref: handler_ref)
    end

    test "is idempotent — second call is a no-op" do
      event_id = Ecto.UUID.generate()
      handler_ref = "Elixir.TestModule:handle"

      assert :ok = CriticalEventDispatcher.mark_processed(event_id, handler_ref)
      assert :ok = CriticalEventDispatcher.mark_processed(event_id, handler_ref)
    end
  end
end
