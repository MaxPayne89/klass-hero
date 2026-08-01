defmodule KlassHero.Test.StubMailerAdapter do
  @moduledoc """
  Mailer adapter for tests: delivers through `Swoosh.Adapters.Test` unless the
  calling process has armed a failure.

  Swoosh ships no way to make delivery fail — `Swoosh.Adapters.Test` and
  `Swoosh.Adapters.Sandbox` both always return `{:ok, _}` — so every worker
  error path that begins with a failed send was untestable. One test
  ("marks reply as failed when delivery fails on final attempt") asserted the
  happy path under a failure name for exactly this reason.

      test "fails the invite once retries are exhausted" do
        StubMailerAdapter.fail_with({:network, :timeout})
        ...
      end

  Arming is per-process, so tests stay `async: true`. It is read from the
  delivering process *and* its `$callers` chain — the same lookup
  `Swoosh.Adapters.Test` uses to find the test process behind a `Task`, so
  arming still bites when delivery happens off the test process.
  """

  use Swoosh.Adapter

  alias Swoosh.Adapters.Test

  @key __MODULE__

  @doc "Arms the calling process so its next deliveries fail with `reason`."
  @spec fail_with(term()) :: :ok
  def fail_with(reason) do
    Process.put(@key, {:error, reason})
    :ok
  end

  @doc "Disarms the calling process, restoring normal delivery."
  @spec deliver_normally() :: :ok
  def deliver_normally do
    Process.delete(@key)
    :ok
  end

  @impl Swoosh.Adapter
  def deliver(email, config) do
    armed_failure() || Test.deliver(email, config)
  end

  @impl Swoosh.Adapter
  def deliver_many(emails, config) do
    armed_failure() || Test.deliver_many(emails, config)
  end

  defp armed_failure do
    [self() | List.wrap(Process.get(:"$callers"))]
    |> Enum.find_value(&armed_failure_for/1)
  end

  # Reads another process's dictionary rather than an ETS table or Agent: arming
  # dies with the test process, so no test can leak a failure into the next one.
  defp armed_failure_for(pid) do
    with {:dictionary, dictionary} <- Process.info(pid, :dictionary),
         {@key, failure} <- List.keyfind(dictionary, @key, 0) do
      failure
    else
      _not_armed -> nil
    end
  end
end
