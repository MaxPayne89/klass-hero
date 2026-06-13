defmodule KlassHero.Shared.Adapters.Driven.Storage.StubStorageAdapter do
  @moduledoc """
  In-memory stub adapter for testing file storage operations.

  Stores files in an Agent for test assertions.
  """

  @behaviour KlassHero.Shared.Domain.Ports.ForStoringFiles

  use Agent

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    Agent.start_link(fn -> %{} end, name: name)
  end

  @impl true
  # Agent may not be started in LiveView integration tests (can't pass custom storage_opts) — store if alive, return stub URL regardless.
  def upload(bucket_type, path, binary, opts) do
    agent = Keyword.get(opts, :agent, __MODULE__)
    key = make_key(bucket_type, path)

    if agent_alive?(agent) do
      Agent.update(agent, fn state ->
        Map.put(state, key, binary)
      end)
    end

    case bucket_type do
      :public -> {:ok, "stub://public/#{path}"}
      :private -> {:ok, path}
    end
  end

  @impl true
  # Agent may not be started in all test setups — return stub URL when not running.
  def signed_url(bucket_type, key, expires_in, opts) do
    agent = Keyword.get(opts, :agent, __MODULE__)

    if agent_alive?(agent) do
      store_key = make_key(bucket_type, key)
      exists? = Agent.get(agent, fn state -> Map.has_key?(state, store_key) end)

      if exists? do
        {:ok, "stub://signed/#{key}?expires=#{expires_in}"}
      else
        {:error, :file_not_found}
      end
    else
      {:ok, "stub://signed/#{key}?expires=#{expires_in}"}
    end
  end

  @impl true
  # Defaults to true when Agent not started (some test setups don't start it).
  def file_exists?(bucket_type, path, opts) do
    agent = Keyword.get(opts, :agent, __MODULE__)
    key = make_key(bucket_type, path)

    if agent_alive?(agent) do
      exists? = Agent.get(agent, fn state -> Map.has_key?(state, key) end)
      {:ok, exists?}
    else
      {:ok, true}
    end
  end

  @impl true
  # Agent may not be started in tests that don't exercise storage (e.g. retention policy tests) — no-op if not running.
  def delete(bucket_type, path, opts) do
    agent = Keyword.get(opts, :agent, __MODULE__)
    key = make_key(bucket_type, path)

    if agent_alive?(agent) do
      Agent.update(agent, fn state ->
        Map.delete(state, key)
      end)
    end

    :ok
  end

  @doc """
  Test helper to retrieve uploaded file content.
  """
  def get_uploaded(bucket_type, path, opts \\ []) do
    agent = Keyword.get(opts, :agent, __MODULE__)
    key = make_key(bucket_type, path)

    case Agent.get(agent, fn state -> Map.get(state, key) end) do
      nil -> {:error, :file_not_found}
      binary -> {:ok, binary}
    end
  end

  @doc """
  Test helper to clear all stored files.
  """
  def clear(opts \\ []) do
    agent = Keyword.get(opts, :agent, __MODULE__)
    Agent.update(agent, fn _state -> %{} end)
  end

  defp agent_alive?(pid) when is_pid(pid), do: Process.alive?(pid)
  defp agent_alive?(name) when is_atom(name), do: Process.whereis(name) != nil

  defp make_key(bucket_type, path), do: "#{bucket_type}:#{path}"
end
