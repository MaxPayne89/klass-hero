defmodule KlassHero.Shared.Adapters.Driven.Storage.StubStorageAdapter do
  @moduledoc """
  In-memory stub adapter for testing file storage operations.

  ## One store per test, resolved from the caller

  Each test owns its own `Agent`, registered in `KlassHero.StorageRegistry` under the
  owning test's pid. Callers that cannot pass options — LiveViews, use cases invoked
  from an Oban job — are reached by walking `$callers` back to that owner, so nothing
  in `lib/` has to know this adapter exists.

  `KlassHero.DataCase` and `KlassHeroWeb.ConnCase` start the owner's store in `setup`,
  which covers every test. A test needing two stores at once (upload here, read there)
  starts extra ones itself and passes `agent:` explicitly; that wins over the walk.

  ## No store means raise, never a plausible answer

  This adapter used to fall back to `{:ok, "stub://signed/..."}` and `{:ok, true}` when
  no `Agent` was running. That made assertions pass for files nobody stored (#1416), so
  a missing owner is now a loud failure.
  """

  @behaviour KlassHero.Shared.ForStoringFiles

  use Agent

  @registry KlassHero.StorageRegistry

  def start_link(opts) do
    case Keyword.fetch(opts, :owner) do
      {:ok, owner} -> Agent.start_link(fn -> %{} end, name: {:via, Registry, {@registry, owner}})
      :error -> Agent.start_link(fn -> %{} end, name: explicit_name!(opts))
    end
  end

  @impl true
  def upload(bucket_type, path, binary, opts) do
    Agent.update(store!(opts), &Map.put(&1, make_key(bucket_type, path), binary))

    case bucket_type do
      :public -> {:ok, "stub://public/#{path}"}
      :private -> {:ok, path}
    end
  end

  @impl true
  def signed_url(bucket_type, key, expires_in, opts) do
    if stored?(opts, bucket_type, key) do
      {:ok, "stub://signed/#{key}?expires=#{expires_in}"}
    else
      {:error, :file_not_found}
    end
  end

  @impl true
  def file_exists?(bucket_type, path, opts) do
    {:ok, stored?(opts, bucket_type, path)}
  end

  @impl true
  def delete(bucket_type, path, opts) do
    Agent.update(store!(opts), &Map.delete(&1, make_key(bucket_type, path)))
    :ok
  end

  @doc """
  Test helper to retrieve uploaded file content.
  """
  def get_uploaded(bucket_type, path, opts \\ []) do
    case Agent.get(store!(opts), &Map.get(&1, make_key(bucket_type, path))) do
      nil -> {:error, :file_not_found}
      binary -> {:ok, binary}
    end
  end

  @doc """
  Test helper to clear all stored files.
  """
  def clear(opts \\ []) do
    Agent.update(store!(opts), fn _state -> %{} end)
  end

  defp stored?(opts, bucket_type, path) do
    Agent.get(store!(opts), &Map.has_key?(&1, make_key(bucket_type, path)))
  end

  defp store!(opts), do: Keyword.get_lazy(opts, :agent, &owned_store!/0)

  defp owned_store!, do: Enum.find_value([self() | callers()], &registered/1) || no_owner!()

  defp callers, do: Process.get(:"$callers", [])

  defp registered(pid) do
    case Registry.lookup(@registry, pid) do
      [{agent, _value}] -> agent
      [] -> nil
    end
  end

  defp no_owner! do
    raise """
    no storage owner for #{inspect(self())} or its $callers.

    Every test owns a stub storage Agent, started for you in KlassHero.DataCase and
    KlassHeroWeb.ConnCase. Reaching this means the calling process is outside that
    test's $callers chain — pass `agent:` explicitly, or start one with
    `start_supervised!({#{inspect(__MODULE__)}, owner: self()})`.

    A Wallaby e2e test cannot get there by either route: a LiveView reached over a
    real websocket carries its transport pid in $callers, not the test's, so no
    ancestry links the two. Storage in `test/e2e/` needs a real adapter, the way
    KlassHero.StorageIntegrationCase points `:storage` at MinIO.
    """
  end

  # A single registered name is what raced across async files in #1416: one file's
  # per-test teardown emptied the store another file was still reading.
  defp explicit_name!(opts) do
    case Keyword.fetch(opts, :name) do
      {:ok, __MODULE__} ->
        raise ArgumentError, """
        #{inspect(__MODULE__)} cannot be registered under its own module name.

        Pass a per-test owner instead — `{#{inspect(__MODULE__)}, owner: self()}` — or a
        unique name when a test genuinely needs a second store.
        """

      {:ok, name} ->
        name

      :error ->
        raise ArgumentError, "#{inspect(__MODULE__)} requires either :owner or a unique :name"
    end
  end

  defp make_key(bucket_type, path), do: "#{bucket_type}:#{path}"
end
