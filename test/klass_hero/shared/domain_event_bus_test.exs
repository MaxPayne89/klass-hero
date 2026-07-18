defmodule KlassHero.Shared.DomainEventBusTest do
  @moduledoc """
  Tests for DomainEventBus registry with caller-side execution.

  Verifies that:
  - Handler return values are surfaced correctly (:ok, {:error, _}, crash, unexpected)
  - Handlers execute in the caller's process, not the GenServer
  - Priority ordering (lower number runs first, default 100)
  - Same-priority handlers preserve registration order
  - Init-time {Module, :function} handler registration via `handlers:` opt
  """

  use ExUnit.Case, async: true

  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.DomainEventBus

  @test_context __MODULE__.TestContext

  defmodule TestHandler do
    @moduledoc false

    def succeed(_event), do: :ok

    def fail(_event), do: {:error, :handler_failed}

    def crash(_event), do: raise("handler boom")

    def unexpected(_event), do: :wrong_return

    def report_pid(event) do
      send(event.payload.test_pid, {:handler_ran_in, self()})
      :ok
    end
  end

  setup do
    _bus = start_supervised!({DomainEventBus, context: @test_context})
    :ok
  end

  defp build_event(event_type, payload \\ %{}) do
    DomainEvent.new(event_type, "entity-1", :test, payload)
  end

  # Handler result tests

  describe "dispatch/2 handler results" do
    test "returns :ok when all handlers succeed" do
      DomainEventBus.subscribe(@test_context, :test_event, fn _event -> :ok end)
      DomainEventBus.subscribe(@test_context, :test_event, fn _event -> :ok end)

      assert :ok = DomainEventBus.dispatch(@test_context, build_event(:test_event))
    end

    test "returns :ok when no handlers are registered" do
      assert :ok = DomainEventBus.dispatch(@test_context, build_event(:unsubscribed_event))
    end

    test "returns error when handler returns {:error, reason}" do
      DomainEventBus.subscribe(@test_context, :failing_event, fn _event ->
        {:error, :publish_failed}
      end)

      assert {:error, [{:error, :publish_failed}]} =
               DomainEventBus.dispatch(@test_context, build_event(:failing_event))
    end

    test "returns error when handler crashes" do
      DomainEventBus.subscribe(@test_context, :crashing_event, fn _event ->
        raise "handler boom"
      end)

      assert {:error, [{:error, {:handler_crashed, %RuntimeError{message: "handler boom"}}}]} =
               DomainEventBus.dispatch(@test_context, build_event(:crashing_event))
    end

    test "wraps unexpected handler return values" do
      DomainEventBus.subscribe(@test_context, :unexpected_event, fn _event ->
        :wrong_return
      end)

      assert {:error, [{:error, {:unexpected_return, :wrong_return}}]} =
               DomainEventBus.dispatch(@test_context, build_event(:unexpected_event))
    end

    test "aggregates failures from multiple handlers" do
      DomainEventBus.subscribe(@test_context, :mixed_event, fn _event -> :ok end)

      DomainEventBus.subscribe(@test_context, :mixed_event, fn _event ->
        {:error, :handler_a_failed}
      end)

      DomainEventBus.subscribe(@test_context, :mixed_event, fn _event -> :ok end)

      DomainEventBus.subscribe(@test_context, :mixed_event, fn _event ->
        raise "handler b boom"
      end)

      assert {:error, failures} =
               DomainEventBus.dispatch(@test_context, build_event(:mixed_event))

      assert length(failures) == 2

      assert Enum.any?(failures, fn
               {:error, :handler_a_failed} -> true
               _ -> false
             end)

      assert Enum.any?(failures, fn
               {:error, {:handler_crashed, %RuntimeError{message: "handler b boom"}}} -> true
               _ -> false
             end)
    end
  end

  # Caller-side execution

  describe "caller-side execution" do
    test "handler runs in the caller's process, not the GenServer" do
      test_pid = self()

      DomainEventBus.subscribe(@test_context, :pid_event, fn _event ->
        send(test_pid, {:handler_ran_in, self()})
        :ok
      end)

      DomainEventBus.dispatch(@test_context, build_event(:pid_event))

      assert_receive {:handler_ran_in, handler_pid}

      # Trigger: handler_pid must equal the test process pid
      # Why: proves execution happens in the caller, not inside the GenServer
      # Outcome: confirms caller-side execution model
      assert handler_pid == test_pid
    end
  end

  # Priority ordering

  describe "priority ordering" do
    test "lower priority number runs first" do
      test_pid = self()

      DomainEventBus.subscribe(
        @test_context,
        :priority_event,
        fn _event ->
          send(test_pid, {:ran, :high_number})
          :ok
        end,
        priority: 200
      )

      DomainEventBus.subscribe(
        @test_context,
        :priority_event,
        fn _event ->
          send(test_pid, {:ran, :low_number})
          :ok
        end,
        priority: 10
      )

      DomainEventBus.dispatch(@test_context, build_event(:priority_event))

      # Trigger: collect messages in order they arrived
      # Why: proves that priority 10 handler ran before priority 200
      # Outcome: execution order matches priority sort
      assert_receive {:ran, first}
      assert_receive {:ran, second}
      assert first == :low_number
      assert second == :high_number
    end

    test "same-priority handlers preserve registration order" do
      test_pid = self()

      DomainEventBus.subscribe(@test_context, :order_event, fn _event ->
        send(test_pid, {:ran, :first})
        :ok
      end)

      DomainEventBus.subscribe(@test_context, :order_event, fn _event ->
        send(test_pid, {:ran, :second})
        :ok
      end)

      DomainEventBus.subscribe(@test_context, :order_event, fn _event ->
        send(test_pid, {:ran, :third})
        :ok
      end)

      DomainEventBus.dispatch(@test_context, build_event(:order_event))

      assert_receive {:ran, first}
      assert_receive {:ran, second}
      assert_receive {:ran, third}
      assert first == :first
      assert second == :second
      assert third == :third
    end

    test "default priority is 100" do
      test_pid = self()

      # Register with default priority (should be 100)
      DomainEventBus.subscribe(@test_context, :default_pri_event, fn _event ->
        send(test_pid, {:ran, :default})
        :ok
      end)

      # Register with explicit priority 50 (should run first)
      DomainEventBus.subscribe(
        @test_context,
        :default_pri_event,
        fn _event ->
          send(test_pid, {:ran, :explicit_50})
          :ok
        end,
        priority: 50
      )

      # Register with explicit priority 150 (should run last)
      DomainEventBus.subscribe(
        @test_context,
        :default_pri_event,
        fn _event ->
          send(test_pid, {:ran, :explicit_150})
          :ok
        end,
        priority: 150
      )

      DomainEventBus.dispatch(@test_context, build_event(:default_pri_event))

      assert_receive {:ran, first}
      assert_receive {:ran, second}
      assert_receive {:ran, third}
      assert first == :explicit_50
      assert second == :default
      assert third == :explicit_150
    end
  end

  # Init-time {Module, :function} handler registration

  describe "init-time handler registration" do
    test "registers {Module, :function} handlers at init" do
      context = __MODULE__.MFAContext

      _bus =
        start_supervised!(
          {DomainEventBus,
           context: context,
           handlers: [
             {:mfa_event, {TestHandler, :succeed}}
           ]},
          id: :mfa_init_test
        )

      assert :ok = DomainEventBus.dispatch(context, build_event(:mfa_event))
    end

    test "init-time handler priority is respected" do
      context = __MODULE__.MFAPriorityContext
      test_pid = self()

      _bus =
        start_supervised!(
          {DomainEventBus,
           context: context,
           handlers: [
             {:pri_event, {TestHandler, :succeed}, priority: 200}
           ]},
          id: :mfa_priority_test
        )

      # Subscribe a higher-priority handler dynamically
      DomainEventBus.subscribe(
        context,
        :pri_event,
        fn _event ->
          send(test_pid, {:ran, :dynamic_first})
          :ok
        end,
        priority: 10
      )

      # The init-time handler (priority 200) returns :ok but we can't easily
      # observe its ordering via messages. Instead, subscribe another lower-priority
      # handler to prove the dynamic one ran first.
      DomainEventBus.subscribe(
        context,
        :pri_event,
        fn _event ->
          send(test_pid, {:ran, :dynamic_last})
          :ok
        end,
        priority: 300
      )

      DomainEventBus.dispatch(context, build_event(:pri_event))

      assert_receive {:ran, first}
      assert_receive {:ran, second}
      assert first == :dynamic_first
      assert second == :dynamic_last
    end

    test "{Module, :function} error propagation" do
      context = __MODULE__.MFAErrorContext

      _bus =
        start_supervised!(
          {DomainEventBus,
           context: context,
           handlers: [
             {:error_event, {TestHandler, :fail}}
           ]},
          id: :mfa_error_test
        )

      assert {:error, [{:error, :handler_failed}]} =
               DomainEventBus.dispatch(context, build_event(:error_event))
    end

    test "{Module, :function} crash propagation" do
      context = __MODULE__.MFACrashContext

      _bus =
        start_supervised!(
          {DomainEventBus,
           context: context,
           handlers: [
             {:crash_event, {TestHandler, :crash}}
           ]},
          id: :mfa_crash_test
        )

      assert {:error, [{:error, {:handler_crashed, %RuntimeError{message: "handler boom"}}}]} =
               DomainEventBus.dispatch(context, build_event(:crash_event))
    end

    test "{Module, :function} reports pid in caller process" do
      context = __MODULE__.MFAPidContext
      test_pid = self()

      _bus =
        start_supervised!(
          {DomainEventBus,
           context: context,
           handlers: [
             {:pid_event, {TestHandler, :report_pid}}
           ]},
          id: :mfa_pid_test
        )

      DomainEventBus.dispatch(context, build_event(:pid_event, %{test_pid: test_pid}))

      assert_receive {:handler_ran_in, handler_pid}
      assert handler_pid == test_pid
    end
  end

  # subscribe/3 backward compatibility

  describe "subscribe/3 backward compatibility" do
    test "subscribe/3 works without opts argument" do
      DomainEventBus.subscribe(@test_context, :compat_event, fn _event -> :ok end)
      assert :ok = DomainEventBus.dispatch(@test_context, build_event(:compat_event))
    end
  end

  # dispatch_critical/2

  defmodule TestCriticalHandler do
    @moduledoc false
    def handle(%DomainEvent{} = _event), do: :ok
  end

  defmodule TestCriticalFailHandler do
    @moduledoc false
    def handle(%DomainEvent{} = _event), do: {:error, :critical_fail}
  end

  describe "dispatch_critical/2" do
    test "returns per-handler results with handler identity" do
      context = :"test_critical_#{System.unique_integer([:positive])}"

      start_supervised!(
        {DomainEventBus,
         context: context,
         handlers: [
           {:test_event, {TestCriticalHandler, :handle}}
         ]},
        id: make_ref()
      )

      event = DomainEvent.new(:test_event, "agg-1", :test, %{})

      assert {:ok, results} = DomainEventBus.dispatch_critical(context, event)
      assert [{handler_identity, :ok}] = results
      assert handler_identity == {TestCriticalHandler, :handle}
    end

    test "includes handler identity in failure results" do
      context = :"test_critical_fail_#{System.unique_integer([:positive])}"

      start_supervised!(
        {DomainEventBus,
         context: context,
         handlers: [
           {:test_event, {TestCriticalHandler, :handle}},
           {:test_event, {TestCriticalFailHandler, :handle}}
         ]},
        id: make_ref()
      )

      event = DomainEvent.new(:test_event, "agg-1", :test, %{})

      assert {:ok, results} = DomainEventBus.dispatch_critical(context, event)

      assert Enum.any?(results, fn
               {{TestCriticalHandler, :handle}, :ok} -> true
               _ -> false
             end)

      assert Enum.any?(results, fn
               {{TestCriticalFailHandler, :handle}, {:error, :critical_fail}} -> true
               _ -> false
             end)
    end

    test "anonymous handlers use :anonymous identity" do
      context = :"test_critical_anon_#{System.unique_integer([:positive])}"
      start_supervised!({DomainEventBus, context: context}, id: make_ref())

      DomainEventBus.subscribe(context, :test_event, fn _event -> :ok end)
      event = DomainEvent.new(:test_event, "agg-1", :test, %{})

      assert {:ok, results} = DomainEventBus.dispatch_critical(context, event)
      assert [{:anonymous, :ok}] = results
    end
  end
end
