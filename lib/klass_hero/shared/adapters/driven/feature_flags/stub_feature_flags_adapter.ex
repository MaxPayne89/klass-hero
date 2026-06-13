defmodule KlassHero.Shared.Adapters.Driven.FeatureFlags.StubFeatureFlagsAdapter do
  @moduledoc """
  In-memory stub for feature flag operations.

  Uses an Agent to store enabled flags as a `MapSet` of atoms.
  Each test can start its own isolated Agent instance via `start_link/1`.

  ## Usage in tests

      setup do
        name = :"flags_#{System.unique_integer([:positive])}"
        {:ok, _pid} = StubFeatureFlagsAdapter.start_link(name: name)
        %{agent: name}
      end

      test "flag is off by default", %{agent: agent} do
        assert {:ok, false} =
                 FeatureFlags.enabled?(:my_flag,
                   adapter: StubFeatureFlagsAdapter,
                   agent: agent
                 )
      end
  """

  @behaviour KlassHero.Shared.Domain.Ports.ForManagingFeatureFlags

  use Agent

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    Agent.start_link(fn -> MapSet.new() end, name: name)
  end

  @impl true
  def enabled?(flag_name, opts) do
    agent = agent(opts)

    if agent_alive?(agent) do
      {:ok, Agent.get(agent, &MapSet.member?(&1, flag_name))}
    else
      {:ok, false}
    end
  end

  @impl true
  def enabled?(flag_name, _actor, opts), do: enabled?(flag_name, opts)

  @impl true
  def enable(flag_name, opts) do
    agent = agent(opts)

    if agent_alive?(agent) do
      Agent.update(agent, &MapSet.put(&1, flag_name))
    end

    :ok
  end

  @impl true
  def disable(flag_name, opts) do
    agent = agent(opts)

    if agent_alive?(agent) do
      Agent.update(agent, &MapSet.delete(&1, flag_name))
    end

    :ok
  end

  @doc "Enable a flag in the stub (test helper)."
  def set_enabled(flag_name, opts \\ []) do
    Agent.update(agent(opts), &MapSet.put(&1, flag_name))
  end

  @doc "Disable a flag in the stub (test helper)."
  def set_disabled(flag_name, opts \\ []) do
    Agent.update(agent(opts), &MapSet.delete(&1, flag_name))
  end

  @doc "Clear all flags in the stub (test helper)."
  def clear(opts \\ []) do
    Agent.update(agent(opts), fn _ -> MapSet.new() end)
  end

  defp agent(opts), do: Keyword.get(opts, :agent, __MODULE__)

  defp agent_alive?(pid) when is_pid(pid), do: Process.alive?(pid)
  defp agent_alive?(name) when is_atom(name), do: Process.whereis(name) != nil
end
