defmodule KlassHero.Shared.ProjectionTest do
  use ExUnit.Case, async: true

  # TestProjection lives inside this file deliberately: the macro must be
  # exercised against a synthetic module backed by an Agent, not a real schema.
  alias KlassHero.Shared.Domain.Events.IntegrationEvent
  alias KlassHero.Shared.Projection

  @agent_name __MODULE__.Agent

  defmodule TestProjection do
    use Projection, topics: ["test:projection:event_a"]

    @agent_name KlassHero.Shared.ProjectionTest.Agent

    @impl Projection
    def bootstrap_impl do
      Agent.update(@agent_name, fn s -> %{s | bootstraps: s.bootstraps + 1} end)
      42
    end

    @impl Projection
    def handle_event(type, event) do
      Agent.update(@agent_name, fn s -> %{s | events: [{type, event} | s.events]} end)
    end
  end

  setup do
    {:ok, agent_pid} =
      Agent.start_link(fn -> %{bootstraps: 0, events: []} end, name: @agent_name)

    on_exit(fn -> if Process.alive?(agent_pid), do: Agent.stop(agent_pid) end)
    :ok
  end

  defp agent_state, do: Agent.get(@agent_name, & &1)

  defp unique_name, do: :"test_proj_#{System.unique_integer([:positive])}"

  describe "start_link/1 with skip_bootstrap: true" do
    test "starts a GenServer that does not subscribe and does not bootstrap" do
      {:ok, pid} =
        TestProjection.start_link(name: unique_name(), skip_bootstrap: true)

      assert Process.alive?(pid)
      assert %{bootstrapped: false} = :sys.get_state(pid)
    end
  end

  describe "handle_continue(:bootstrap, ...)" do
    test "invokes bootstrap_impl/0 and marks state bootstrapped" do
      {:ok, pid} = TestProjection.start_link(name: unique_name())
      :sys.get_state(pid)

      assert %{bootstrapped: true} = :sys.get_state(pid)
      assert agent_state().bootstraps == 1
    end
  end

  describe "init/1 with default opts" do
    test "subscribes to every topic in :topics" do
      name = unique_name()
      {:ok, pid} = TestProjection.start_link(name: name)
      :sys.get_state(pid)

      # If subscription works, broadcasting to the topic delivers to the GenServer mailbox.
      event = %IntegrationEvent{
        event_id: Ecto.UUID.generate(),
        event_type: :event_a,
        source_context: :test,
        entity_type: :thing,
        entity_id: "id-1",
        occurred_at: DateTime.utc_now(),
        payload: %{},
        metadata: %{},
        version: 1
      }

      Phoenix.PubSub.broadcast(KlassHero.PubSub, "test:projection:event_a", {:integration_event, event})
      :sys.get_state(pid)

      # If the event was received, handle_event was called and recorded it.
      assert [{:event_a, ^event}] = agent_state().events
    end
  end
end
