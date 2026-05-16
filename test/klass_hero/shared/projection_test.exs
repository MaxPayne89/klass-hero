defmodule KlassHero.Shared.ProjectionTest do
  use ExUnit.Case, async: true

  # TestProjection lives inside this file deliberately: the macro must be
  # exercised against a synthetic module backed by an Agent, not a real schema.
  alias KlassHero.Shared.Projection

  defmodule TestProjection do
    use Projection, topics: ["test:projection:event_a"]

    @impl Projection
    def bootstrap_impl, do: 0

    @impl Projection
    def handle_event(_type, _event), do: :ok
  end

  describe "start_link/1 with skip_bootstrap: true" do
    test "starts a GenServer that does not subscribe and does not bootstrap" do
      {:ok, pid} =
        TestProjection.start_link(name: unique_name(), skip_bootstrap: true)

      assert Process.alive?(pid)
      assert %{bootstrapped: false} = :sys.get_state(pid)
    end
  end

  defp unique_name, do: :"test_proj_#{System.unique_integer([:positive])}"
end
