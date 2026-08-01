defmodule KlassHero.ProjectionSupervisorTest do
  @moduledoc """
  Guards `projections/0` against the projection modules that actually exist.

  That list is not derived from anything — it is hand-written, and three separate
  things trust it completely: the supervisor starts what it names, the consumer
  wiring test only checks what it names, and `rebuild_all/0` only rebuilds what it
  names. A projection missing from it therefore has no supervisor, no wiring
  coverage and no rebuild, and every one of those failures is silent: the read
  table is simply empty, which is indistinguishable from a feature with no data
  yet.
  """

  use ExUnit.Case, async: true

  alias KlassHero.ProjectionSupervisor

  # `use KlassHero.Shared.Projection` is what defines both of these, so exporting
  # the pair identifies a projection without the macro having to register itself.
  defp projection_modules do
    {:ok, modules} = :application.get_key(:klass_hero, :modules)

    for module <- modules,
        Code.ensure_loaded?(module),
        function_exported?(module, :rebuild, 1),
        function_exported?(module, :topics, 0),
        do: module
  end

  test "every projection module is registered in projections/0" do
    unregistered = projection_modules() -- ProjectionSupervisor.projections()

    assert unregistered == [],
           """
           Projection modules absent from ProjectionSupervisor.projections/0: \
           #{inspect(unregistered)}
           They are unsupervised, unrebuilt by the seeds, and invisible to the event
           consumer wiring test. Add them to `projections/0` in
           lib/klass_hero/projection_supervisor.ex.
           """
  end

  test "projections/0 names no module that has stopped being a projection" do
    stale = ProjectionSupervisor.projections() -- projection_modules()

    assert stale == [],
           """
           ProjectionSupervisor.projections/0 names modules that are no longer \
           projections: #{inspect(stale)}
           Deleting a projection means deleting its entry here too — #1222 was a \
           dangling entry like this reaching priv/repo/seeds.exs.
           """
  end
end
