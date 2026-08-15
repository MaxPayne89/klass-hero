defmodule KlassHero.Shared.EventDispatcherTest do
  use KlassHero.DataCase, async: true

  import ExUnit.CaptureLog

  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.Schemas.ProcessedEvent
  alias KlassHero.Shared.EventDispatcher

  describe "handler_ref/1" do
    test "produces canonical string from {module, function} tuple" do
      ref = EventDispatcher.handler_ref({MyApp.SomeHandler, :handle_event})
      assert ref == "Elixir.MyApp.SomeHandler:handle_event"
    end

    test "produces different refs for different functions on same module" do
      ref_a = EventDispatcher.handler_ref({MyApp.Handler, :handle})
      ref_b = EventDispatcher.handler_ref({MyApp.Handler, :handle_event})
      assert ref_a != ref_b
    end
  end

  describe "execute/3" do
    test "runs handler and inserts processed_events row on success" do
      event_id = Ecto.UUID.generate()
      handler_ref = "Elixir.TestModule:handle"
      test_pid = self()

      result =
        EventDispatcher.execute(event_id, handler_ref, fn ->
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
        EventDispatcher.execute(event_id, handler_ref, fn ->
          send(test_pid, :first_call)
          :ok
        end)

      assert_received :first_call

      # Second call is idempotent — handler not called
      :ok =
        EventDispatcher.execute(event_id, handler_ref, fn ->
          send(test_pid, :second_call)
          :ok
        end)

      refute_received :second_call
    end

    test "rolls back processed_events row on handler failure" do
      event_id = Ecto.UUID.generate()
      handler_ref = "Elixir.TestModule:handle"

      result =
        EventDispatcher.execute(event_id, handler_ref, fn ->
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
        EventDispatcher.execute(event_id, handler_ref, fn ->
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
        EventDispatcher.execute(event_id, handler_ref, fn ->
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
          EventDispatcher.execute(event_id, handler_ref, fn ->
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
        EventDispatcher.execute(event_id, handler_ref, fn ->
          {:error, :transient}
        end)

      # Retry succeeds — row was not left behind
      :ok =
        EventDispatcher.execute(event_id, handler_ref, fn ->
          send(test_pid, :retry_succeeded)
          :ok
        end)

      assert_received :retry_succeeded
      assert Repo.get_by(ProcessedEvent, event_id: event_id, handler_ref: handler_ref)
    end
  end
end
