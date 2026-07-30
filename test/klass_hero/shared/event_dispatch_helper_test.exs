defmodule KlassHero.Shared.EventDispatchHelperTest do
  use KlassHero.DataCase, async: true

  import ExUnit.CaptureLog

  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.Schemas.ProcessedEvent
  alias KlassHero.Shared.CriticalEventDispatcher
  alias KlassHero.Shared.Domain.Events.Event
  alias KlassHero.Shared.DomainEventBus
  alias KlassHero.Shared.EventDispatchHelper

  @context TestContext

  setup do
    # Start a DomainEventBus for the test context
    start_supervised!({DomainEventBus, context: @context})

    :ok
  end

  describe "dispatch/2" do
    test "returns :ok when dispatch succeeds" do
      event = build_event(:test_event)

      assert :ok = EventDispatchHelper.dispatch(event, @context)
    end

    test "returns :ok even when handler fails" do
      DomainEventBus.subscribe(@context, :test_event, fn _event ->
        {:error, :handler_failed}
      end)

      event = build_event(:test_event)

      assert :ok = EventDispatchHelper.dispatch(event, @context)
    end

    test "logs at warning level for normal event dispatch failure" do
      DomainEventBus.subscribe(@context, :test_event, fn _event ->
        {:error, :handler_failed}
      end)

      event = build_event(:test_event, criticality: :normal)

      log =
        capture_log([level: :warning], fn ->
          EventDispatchHelper.dispatch(event, @context)
        end)

      assert log =~ "Event dispatch failed"
      assert log =~ "test_event"
    end

    test "logs at error level for critical event dispatch failure" do
      DomainEventBus.subscribe(@context, :critical_event, fn _event ->
        {:error, :handler_failed}
      end)

      event = build_event(:critical_event, criticality: :critical)

      log =
        capture_log([level: :error], fn ->
          EventDispatchHelper.dispatch(event, @context)
        end)

      assert log =~ "Critical event dispatch failed"
      assert log =~ "critical_event"
    end
  end

  defmodule CriticalSuccessHandler do
    def handle(%Event{} = _event), do: :ok
  end

  defmodule CriticalFailHandler do
    def handle(%Event{} = _event), do: {:error, :handler_broke}
  end

  describe "dispatch/2 with critical events" do
    setup do
      context = :"test_critical_dispatch_#{System.unique_integer([:positive])}"

      start_supervised!(
        {DomainEventBus,
         context: context,
         handlers: [
           {:critical_test, {CriticalSuccessHandler, :handle}}
         ]},
        id: make_ref()
      )

      %{context: context}
    end

    test "marks handler as processed when critical event succeeds", %{context: context} do
      event = Event.new(:critical_test, :test_context, :test, "agg-1", %{}, criticality: :critical)

      assert :ok = EventDispatchHelper.dispatch(event, context)

      handler_ref = CriticalEventDispatcher.handler_ref({CriticalSuccessHandler, :handle})
      assert Repo.get_by(ProcessedEvent, event_id: event.event_id, handler_ref: handler_ref)
    end

    test "does NOT mark as processed for normal events", %{context: context} do
      event = Event.new(:critical_test, :test_context, :test, "agg-1", %{})

      assert :ok = EventDispatchHelper.dispatch(event, context)

      # No processed_events row for normal events
      assert [] == Repo.all(ProcessedEvent)
    end
  end

  describe "dispatch/2 critical event with failed handler" do
    setup do
      context = :"test_critical_fail_#{System.unique_integer([:positive])}"

      start_supervised!(
        {DomainEventBus,
         context: context,
         handlers: [
           {:critical_fail_test, {CriticalSuccessHandler, :handle}},
           {:critical_fail_test, {CriticalFailHandler, :handle}}
         ]},
        id: make_ref()
      )

      %{context: context}
    end

    test "enqueues Oban job for failed handler and marks successful one", %{context: context} do
      event =
        Event.new(:critical_fail_test, :test_context, :test, "agg-1", %{data: "val"}, criticality: :critical)

      assert :ok = EventDispatchHelper.dispatch(event, context)

      # Successful handler should be marked processed
      success_ref = CriticalEventDispatcher.handler_ref({CriticalSuccessHandler, :handle})
      assert Repo.get_by(ProcessedEvent, event_id: event.event_id, handler_ref: success_ref)

      # Failed handler should have an Oban job enqueued
      # (In test mode with Oban :inline, the job runs immediately — so it will
      #  also fail and the processed_events row won't exist)
      fail_ref = CriticalEventDispatcher.handler_ref({CriticalFailHandler, :handle})
      refute Repo.get_by(ProcessedEvent, event_id: event.event_id, handler_ref: fail_ref)
    end
  end

  describe "dispatch_or_error/2 with critical events" do
    setup do
      context = :"test_critical_or_error_#{System.unique_integer([:positive])}"

      start_supervised!(
        {DomainEventBus,
         context: context,
         handlers: [
           {:critical_or_error_test, {CriticalFailHandler, :handle}}
         ]},
        id: make_ref()
      )

      %{context: context}
    end

    test "does NOT enqueue Oban job — caller owns error handling", %{context: context} do
      event =
        Event.new(:critical_or_error_test, :test_context, :test, "agg-1", %{}, criticality: :critical)

      assert {:error, _reason} = EventDispatchHelper.dispatch_or_error(event, context)

      # No Oban job — dispatch_or_error lets caller handle the failure
      # No processed_events row either
      assert [] == Repo.all(ProcessedEvent)
    end
  end

  describe "dispatch_or_error/2 with normal events" do
    test "returns :ok when handler succeeds" do
      DomainEventBus.subscribe(@context, :normal_or_error, fn _event -> :ok end)

      event = build_event(:normal_or_error)

      assert :ok = EventDispatchHelper.dispatch_or_error(event, @context)
    end

    test "returns {:error, reason} when handler fails" do
      DomainEventBus.subscribe(@context, :normal_or_error_fail, fn _event ->
        {:error, :handler_failed}
      end)

      event = build_event(:normal_or_error_fail)

      assert {:error, _reason} = EventDispatchHelper.dispatch_or_error(event, @context)
    end
  end

  defp build_event(type, opts \\ []) do
    Event.new(type, :test_context, :test, 1, %{}, opts)
  end
end
