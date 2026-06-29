# Caller defined outside the test module to avoid the import conflict between
# TracingHelpers.span (record accessor) and Tracing.span (macro).
defmodule KlassHero.Shared.Tracing.EctoSpanBridgeTest.Caller do
  use KlassHero.Shared.Tracing

  import Ecto.Query

  alias KlassHero.Repo

  @doc "Runs a parameterised query INSIDE a parent span."
  def query_in_span do
    span "parent.span" do
      run_query()
    end
  end

  @doc "Runs the same query with NO enclosing span."
  def query_no_span, do: run_query()

  defp run_query do
    Repo.all(from(c in "children", where: c.id == type(^Ecto.UUID.generate(), :binary_id), select: c.id))
  end
end

defmodule KlassHero.Shared.Tracing.EctoSpanBridgeTest do
  use KlassHero.DataCase, async: false
  use KlassHero.TracingHelpers

  alias KlassHero.Shared.Tracing.EctoSpanBridgeTest.Caller

  describe "Ecto query -> OTel span bridge" do
    test "emits a child db span for a query run inside a parent span" do
      Caller.query_in_span()

      span = assert_span("children.query")
      attrs = span_attributes(span)

      assert attrs["db.system"] == "postgresql"
      assert attrs["db.source"] == "children"
      assert is_number(attrs["db.total_time_ms"])
    end

    test "tags the parameterised statement but no raw param values" do
      Caller.query_in_span()

      span = assert_span("children.query")
      attrs = span_attributes(span)

      # Parameterised SQL keeps placeholders ($1), never inlined values.
      assert is_binary(attrs["db.statement"])
      assert attrs["db.statement"] =~ "$1"
      # PII default-deny: param VALUES never leave the process.
      refute Map.has_key?(attrs, "db.params")
    end

    test "emits nothing for a query with no enclosing span (child-only)" do
      Caller.query_no_span()

      flush_spans()
      refute_receive {:span, _}, 200
    end
  end
end
