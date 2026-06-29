defmodule KlassHero.Family.ObservabilityTest do
  @moduledoc """
  Proves Option E end-to-end on the flattened Family context: a public context
  function opens a coarse `context_span`, under which the Ecto bridge nests a
  fine-grained `*.query` child span — with no per-call instrumentation in the
  context body.
  """

  use KlassHero.DataCase, async: false
  use KlassHero.TracingHelpers

  alias KlassHero.Family

  @valid_attrs %{first_name: "Emma", last_name: "Smith", date_of_birth: ~D[2015-06-15]}

  describe "context_span + Ecto bridge integration" do
    test "create_child opens a context span with a nested db child span" do
      assert {:ok, _child} = Family.create_child(@valid_attrs)

      assert_span("Family.create_child/1",
        "context.name": "Family",
        "context.operation": "create_child"
      )

      assert_span("children.query")
    end
  end
end
