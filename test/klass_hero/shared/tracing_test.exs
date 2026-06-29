# Defined outside the test module to avoid import conflict between
# TracingHelpers.span (record accessor) and Tracing.span (macro).
defmodule KlassHero.Shared.TracingTest.TestAdapter do
  use KlassHero.Shared.Tracing

  def traced_operation do
    span do
      :result
    end
  end

  def traced_with_name do
    span "custom.span_name" do
      :named_result
    end
  end

  def traced_with_attributes do
    span do
      set_attribute("db.operation", "insert")
      set_attribute("db.entity", "enrollment")
      :attributed_result
    end
  end

  def traced_with_error do
    span do
      raise ArgumentError, "test error"
    end
  end

  def traced_with_numeric_attribute do
    span do
      set_attribute("http.status_code", 200)
      :ok
    end
  end

  def traced_with_namespaced_attributes do
    span do
      set_attributes("db", operation: "insert", entity: "enrollment")
      :ok
    end
  end

  def traced_with_atom_attribute do
    span do
      set_attribute("status", :pending)
      :ok
    end
  end

  def traced_with_complex_attribute do
    span do
      set_attribute("debug", %{a: 1})
      :ok
    end
  end

  def traced_with_boolean_attribute do
    span do
      set_attribute("flag", true)
      :ok
    end
  end

  def context_traced do
    context_span do
      :ctx_result
    end
  end

  def context_traced_with_attrs do
    context_span entity: "child" do
      :ok
    end
  end
end

defmodule KlassHero.Shared.TracingTest do
  use ExUnit.Case, async: false
  use KlassHero.TracingHelpers

  alias KlassHero.Shared.TracingTest.TestAdapter

  describe "span/1 with auto-naming" do
    test "creates a span named from module and function" do
      assert :result == TestAdapter.traced_operation()
      assert_span("Shared.TracingTest.TestAdapter.traced_operation/0")
    end

    test "returns the block's result" do
      assert :result == TestAdapter.traced_operation()
    end
  end

  describe "span/2 with explicit name" do
    test "creates a span with the given name" do
      assert :named_result == TestAdapter.traced_with_name()
      assert_span("custom.span_name")
    end
  end

  describe "set_attribute/2" do
    test "sets string attributes on the current span" do
      TestAdapter.traced_with_attributes()

      assert_span("Shared.TracingTest.TestAdapter.traced_with_attributes/0",
        "db.operation": "insert",
        "db.entity": "enrollment"
      )
    end

    test "preserves numeric attribute types" do
      TestAdapter.traced_with_numeric_attribute()

      assert_span("Shared.TracingTest.TestAdapter.traced_with_numeric_attribute/0",
        "http.status_code": 200
      )
    end

    test "converts atom values to strings" do
      TestAdapter.traced_with_atom_attribute()

      assert_span("Shared.TracingTest.TestAdapter.traced_with_atom_attribute/0",
        status: "pending"
      )
    end

    test "inspects complex types (maps, lists)" do
      TestAdapter.traced_with_complex_attribute()

      assert_span("Shared.TracingTest.TestAdapter.traced_with_complex_attribute/0",
        debug: inspect(%{a: 1})
      )
    end

    test "preserves boolean values" do
      TestAdapter.traced_with_boolean_attribute()

      assert_span("Shared.TracingTest.TestAdapter.traced_with_boolean_attribute/0",
        flag: true
      )
    end
  end

  describe "set_attributes/2" do
    test "prefixes keys with namespace" do
      TestAdapter.traced_with_namespaced_attributes()

      assert_span("Shared.TracingTest.TestAdapter.traced_with_namespaced_attributes/0",
        "db.operation": "insert",
        "db.entity": "enrollment"
      )
    end
  end

  describe "context_span" do
    test "creates a span named for the context function with context attributes" do
      assert :ctx_result == TestAdapter.context_traced()

      assert_span("Shared.TracingTest.TestAdapter.context_traced/0",
        "context.name": "TestAdapter",
        "context.operation": "context_traced"
      )
    end

    test "forwards extra opts as context.* attributes" do
      TestAdapter.context_traced_with_attrs()

      assert_span("Shared.TracingTest.TestAdapter.context_traced_with_attrs/0",
        "context.name": "TestAdapter",
        "context.operation": "context_traced_with_attrs",
        "context.entity": "child"
      )
    end
  end

  describe "exception handling" do
    test "records exception on span and reraises" do
      assert_raise ArgumentError, "test error", fn ->
        TestAdapter.traced_with_error()
      end

      span = assert_span("Shared.TracingTest.TestAdapter.traced_with_error/0")
      attrs = span_attributes(span)

      assert attrs["exception.type"] == "ArgumentError"
      assert attrs["exception.message"] == "test error"
      assert is_binary(attrs["exception.stacktrace"])
      assert span_status_code(span) == :error
    end
  end
end
