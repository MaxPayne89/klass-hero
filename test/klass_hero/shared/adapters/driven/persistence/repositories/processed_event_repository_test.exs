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
end
