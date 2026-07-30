defmodule KlassHero.Shared.ProjectionTest do
  use ExUnit.Case, async: true

  # TestProjection lives inside this file deliberately: the macro must be
  # exercised against a synthetic module backed by an Agent, not a real schema.
  alias KlassHero.Shared.Domain.Events.IntegrationEvent
  alias KlassHero.Shared.Projection
  alias KlassHero.Shared.ProjectionTest.AlwaysFailAgent
  alias KlassHero.Shared.ProjectionTest.FlakyAgent
  alias KlassHero.Shared.ProjectionTest.InstantSuccessAgent

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

  defmodule IntegrationTopicProjection do
    use Projection, topics: ["integration:test:event_a"]

    @agent_name KlassHero.Shared.ProjectionTest.Agent

    @impl Projection
    def bootstrap_impl, do: 0

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

  describe "rebuild/1" do
    test "re-invokes bootstrap_impl/0 and stays bootstrapped" do
      {:ok, pid} = TestProjection.start_link(name: unique_name())
      :sys.get_state(pid)
      assert agent_state().bootstraps == 1

      assert :ok = TestProjection.rebuild(pid)

      assert agent_state().bootstraps == 2
      assert %{bootstrapped: true} = :sys.get_state(pid)
    end
  end

  describe "project/1" do
    test "routes the event to handle_event/2 in the caller's process" do
      event = integration_event(:event_a)

      assert :ok = TestProjection.project(event)

      assert [{:event_a, ^event}] = agent_state().events
    end

    # The delivery job calls project/1 directly, so a projection must not also be
    # subscribed to its integration topics — that would double-apply every event on
    # whichever node happened to run the job.
    test "is the only route in: an integration topic is not subscribed" do
      {:ok, pid} = IntegrationTopicProjection.start_link(name: unique_name())
      :sys.get_state(pid)

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:test:event_a",
        {:integration_event, integration_event(:event_a)}
      )

      :sys.get_state(pid)

      assert [] = agent_state().events
    end
  end

  defp integration_event(type) do
    %IntegrationEvent{
      event_id: Ecto.UUID.generate(),
      event_type: type,
      source_context: :test,
      entity_type: :thing,
      entity_id: "id-1",
      occurred_at: DateTime.utc_now(),
      payload: %{},
      metadata: %{},
      version: 1
    }
  end

  describe ":retry_bootstrap message" do
    test "re-enters handle_continue(:bootstrap, _)" do
      {:ok, pid} = TestProjection.start_link(name: unique_name())
      :sys.get_state(pid)
      assert agent_state().bootstraps == 1

      send(pid, :retry_bootstrap)
      :sys.get_state(pid)

      assert agent_state().bootstraps == 2
    end
  end

  describe "catch-all handle_info/2" do
    import ExUnit.CaptureLog

    test "logs a warning and continues" do
      {:ok, pid} = TestProjection.start_link(name: unique_name(), skip_bootstrap: true)

      log =
        capture_log(fn ->
          send(pid, {:wat, "unexpected"})
          :sys.get_state(pid)
        end)

      assert log =~ "received unexpected message"
      assert Process.alive?(pid)
    end
  end

  defmodule FlakyProjection do
    use Projection, topics: ["test:flaky:event"]

    use KlassHero.Shared.Projection.WithBootstrapRetry,
      max_attempts: 2,
      base_delay_ms: 10

    @impl Projection
    def bootstrap_impl do
      attempts =
        Agent.get_and_update(
          FlakyAgent,
          fn n -> {n + 1, n + 1} end
        )

      if attempts == 1 do
        raise "first attempt fails"
      else
        attempts
      end
    end

    @impl Projection
    def handle_event(_, _), do: :ok
  end

  defmodule InstantSuccessProjection do
    use Projection, topics: ["test:instant_success:event"]

    use KlassHero.Shared.Projection.WithBootstrapRetry,
      max_attempts: 3,
      base_delay_ms: 100

    @impl Projection
    def bootstrap_impl do
      Agent.update(InstantSuccessAgent, fn n -> n + 1 end)
      7
    end

    @impl Projection
    def handle_event(_, _), do: :ok
  end

  defmodule AlwaysFailingProjection do
    use Projection, topics: ["test:always_fails:event"]

    use KlassHero.Shared.Projection.WithBootstrapRetry,
      max_attempts: 2,
      base_delay_ms: 5

    @impl Projection
    def bootstrap_impl do
      # Raise behind a runtime condition (always true: count starts at 0 and is
      # incremented before the check) so the return type stays integer() instead
      # of none() — Elixir 1.20's inference otherwise flags the macro-generated
      # `count = bootstrap_impl()` match as unreachable.
      count = Agent.get_and_update(AlwaysFailAgent, fn n -> {n + 1, n + 1} end)
      if count > 0, do: raise("always fails")
      count
    end

    @impl Projection
    def handle_event(_, _), do: :ok
  end

  describe "WithBootstrapRetry mixin" do
    setup do
      {:ok, flaky_pid} =
        Agent.start_link(fn -> 0 end, name: FlakyAgent)

      on_exit(fn -> if Process.alive?(flaky_pid), do: Agent.stop(flaky_pid) end)
      :ok
    end

    test "retries after a transient bootstrap failure and eventually succeeds" do
      import ExUnit.CaptureLog

      log =
        capture_log(fn ->
          {:ok, pid} = FlakyProjection.start_link(name: unique_name())

          # No synchronous signal for async handle_continue completion via :retry_bootstrap.
          # First attempt rescues; retry scheduled at base_delay * attempt = 10ms.
          Process.sleep(100)
          assert %{bootstrapped: true} = :sys.get_state(pid)
        end)

      assert log =~ "bootstrap failed, scheduling retry"
      assert Agent.get(FlakyAgent, & &1) == 2
    end

    test "succeeds on first attempt without retry without crashing" do
      {:ok, instant_pid} = Agent.start_link(fn -> 0 end, name: InstantSuccessAgent)
      on_exit(fn -> if Process.alive?(instant_pid), do: Agent.stop(instant_pid) end)
      {:ok, pid} = InstantSuccessProjection.start_link(name: unique_name())

      # Drain handle_continue. With the bug present, the GenServer crashes here
      # with KeyError because state lacks :retry_count and the success path
      # used %{state | retry_count: 0}.
      :sys.get_state(pid)

      assert %{bootstrapped: true, retry_count: 0} = :sys.get_state(pid)
      assert Agent.get(InstantSuccessAgent, & &1) == 1
    end

    test "reraises after max_attempts consecutive failures" do
      import ExUnit.CaptureLog

      {:ok, always_fail_pid} =
        Agent.start_link(fn -> 0 end, name: AlwaysFailAgent)

      on_exit(fn ->
        if Process.alive?(always_fail_pid), do: Agent.stop(always_fail_pid)
      end)

      Process.flag(:trap_exit, true)

      capture_log(fn ->
        {:ok, pid} = AlwaysFailingProjection.start_link(name: unique_name())

        # First attempt fails inside handle_continue. Retry mixin reschedules
        # at base_delay_ms * 1 = 5ms; second attempt fails and reschedules at 10ms;
        # third attempt fails — reraises and crashes the GenServer.
        assert_receive {:EXIT, ^pid, _reason}, 200
      end)

      # 3 attempts total: initial + 2 retries.
      assert Agent.get(AlwaysFailAgent, & &1) == 3
    end
  end
end
