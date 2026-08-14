# Helper modules defined outside the test module to avoid import conflict between
# TracingHelpers.span (record accessor) and Tracing.span (macro).
defmodule KlassHero.Shared.Tracing.ContextTest.Helpers do
  use KlassHero.Shared.Tracing

  alias KlassHero.Shared.Domain.Events.Event
  alias KlassHero.Shared.Tracing.Context

  def inject_in_span do
    span "parent.operation" do
      context = Context.inject()

      task =
        Task.async(fn ->
          Context.attach(context)

          span "child.operation" do
            :child_result
          end
        end)

      Task.await(task)
      context
    end
  end

  def inject_into_domain_event do
    span "test.operation" do
      event = Event.new(:test_event, :test_context, :test, "123", %{})
      Context.inject_into_event(event)
    end
  end

  def inject_into_integration_event do
    span "test.operation" do
      event = Event.new(:test_event, :test, :entity, "123", %{})
      Context.inject_into_event(event)
    end
  end

  def attach_from_event_in_child_span do
    span "publisher.span" do
      event = Event.new(:test_event, :test_context, :test, "123", %{})
      enriched = Context.inject_into_event(event)

      task =
        Task.async(fn ->
          Context.attach_from_event(enriched)

          span "subscriber.span" do
            :ok
          end
        end)

      Task.await(task)
    end
  end

  def attach_with_mixed_keys_in_child_span do
    span "parent.operation" do
      context = Context.inject()
      mixed = Map.put(context, :correlation_id, "corr-1")

      task =
        Task.async(fn ->
          Context.attach(mixed)

          span "child.operation" do
            :ok
          end
        end)

      Task.await(task)
      context
    end
  end

  def inject_into_args_and_attach_in_child_span do
    span "enqueue.operation" do
      args = %{"invite_id" => "abc123"}
      enriched_args = Context.inject_into_args(args)

      task =
        Task.async(fn ->
          Context.attach_from_args(enriched_args)

          span "worker.operation" do
            :ok
          end
        end)

      Task.await(task)
      enriched_args
    end
  end
end

defmodule KlassHero.Shared.Tracing.ContextTest do
  use ExUnit.Case, async: false
  use KlassHero.TracingHelpers

  alias KlassHero.Shared.Tracing.Context
  alias KlassHero.Shared.Tracing.ContextTest.Helpers

  # Span isolation (flush + drain between tests) is provided by the shared
  # `use KlassHero.TracingHelpers` setup.

  describe "inject/0 and attach/1" do
    test "roundtrips trace context across processes" do
      context = Helpers.inject_in_span()

      assert is_map(context)
      assert Map.has_key?(context, "traceparent")

      parent_span = assert_span("parent.operation")
      child_span = assert_span("child.operation")

      assert span(parent_span, :trace_id) == span(child_span, :trace_id)
    end

    test "filters atom keys and attaches only binary-keyed trace context" do
      Helpers.attach_with_mixed_keys_in_child_span()

      parent_span = assert_span("parent.operation")
      child_span = assert_span("child.operation")

      assert span(parent_span, :trace_id) == span(child_span, :trace_id)
    end
  end

  describe "inject/0 when no active span" do
    test "returns empty map" do
      assert Context.inject() == %{}
    end
  end

  describe "inject_into_event/1" do
    test "merges trace context into DomainEvent metadata" do
      enriched = Helpers.inject_into_domain_event()

      assert Map.has_key?(enriched.metadata, "traceparent")
      assert enriched.event_type == :test_event
    end

    test "merges trace context into Event metadata" do
      enriched = Helpers.inject_into_integration_event()

      assert Map.has_key?(enriched.metadata, "traceparent")
    end
  end

  describe "attach_from_event/1" do
    test "restores context from event metadata" do
      Helpers.attach_from_event_in_child_span()

      subscriber_span = assert_span("subscriber.span")
      assert span(subscriber_span, :parent_span_id) != :undefined
    end
  end

  describe "inject_into_args/1 and attach_from_args/1" do
    test "roundtrips trace context through job args" do
      enriched_args = Helpers.inject_into_args_and_attach_in_child_span()

      assert is_map(enriched_args["trace_context"])
      assert enriched_args["invite_id"] == "abc123"

      worker_span = assert_span("worker.operation")
      assert span(worker_span, :parent_span_id) != :undefined
    end
  end

  describe "attach_from_args/1 with no trace context" do
    test "is a no-op when trace_context key is missing" do
      args = %{"invite_id" => "abc123"}
      assert :ok == Context.attach_from_args(args)
    end
  end
end
