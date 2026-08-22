defmodule KlassHero.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use KlassHero.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox
  alias KlassHero.Shared.Adapters.Driven.Storage.StubStorageAdapter

  using do
    quote do
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import KlassHero.DataCase

      alias KlassHero.Repo
    end
  end

  setup tags do
    KlassHero.DataCase.setup_sandbox(tags)
    KlassHero.DataCase.setup_storage()
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(KlassHero.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end

  @doc """
  Gives this test its own stub storage store, keyed by the test pid.

  `StubStorageAdapter` walks `$callers` back to that pid, so a LiveView or an inline
  Oban job reads and writes the same store without any `lib/` caller passing options.
  A test wanting a second store starts one itself and passes `agent:`.
  """
  def setup_storage do
    start_supervised!({StubStorageAdapter, owner: self()})
    :ok
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  @doc """
  Polls `fun` until it returns a truthy value, or flunks after `timeout_ms`.

  Useful for asserting on async state changes (e.g., PubSub-driven profile creation).

  ## Options

    * `:timeout_ms` - max wait time (default: 2000)
    * `:interval_ms` - polling interval (default: 50)
  """
  def assert_eventually(fun, opts \\ []) do
    timeout = Keyword.get(opts, :timeout_ms, 2000)
    interval = Keyword.get(opts, :interval_ms, 50)
    deadline = System.monotonic_time(:millisecond) + timeout
    do_assert_eventually(fun, interval, deadline)
  end

  defp do_assert_eventually(fun, interval, deadline) do
    if fun.() do
      :ok
    else
      if System.monotonic_time(:millisecond) > deadline do
        import ExUnit.Assertions

        flunk("Expected condition was not met within timeout")
      else
        Process.sleep(interval)
        do_assert_eventually(fun, interval, deadline)
      end
    end
  end
end
