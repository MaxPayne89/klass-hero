# Helper modules defined outside the test module to avoid import conflict between
# TracingHelpers.span (record accessor) and Tracing.span (macro).
defmodule KlassHero.Shared.Tracing.ContextTest.Helpers do
  use KlassHero.Shared.Tracing

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

      assert Map.has_key?(context, "traceparent")

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

  describe "inject_into_args/1 and attach_from_args/1" do
    test "roundtrips trace context through job args" do
      enriched_args = Helpers.inject_into_args_and_attach_in_child_span()

      assert Map.has_key?(enriched_args["trace_context"], "traceparent")
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
