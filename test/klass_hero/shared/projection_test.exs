defmodule KlassHero.Shared.ProjectionTest do
  use ExUnit.Case, async: true

  # TestProjection lives inside this file deliberately: the macro must be
  # exercised against a synthetic module backed by an Agent, not a real schema.
  alias KlassHero.Shared.Projection

  defmodule TestProjection do
    use Projection, topics: ["test:projection:event_a"]

    @impl Projection
    def bootstrap_impl do
      Agent.update(:projection_test_agent, fn s -> %{s | bootstraps: s.bootstraps + 1} end)
      42
    end

    @impl Projection
    def handle_event(type, event) do
      Agent.update(:projection_test_agent, fn s -> %{s | events: [{type, event} | s.events]} end)
    end
  end

  setup do
    {:ok, agent_pid} =
      Agent.start_link(fn -> %{bootstraps: 0, events: []} end, name: :projection_test_agent)

    on_exit(fn -> if Process.alive?(agent_pid), do: Agent.stop(agent_pid) end)
    :ok
  end

  defp agent_state, do: Agent.get(:projection_test_agent, & &1)

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
end
