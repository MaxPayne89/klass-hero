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

  # async: false on purpose. Finding the projections means asking whether each of the
  # ~410 application modules exports the pair, and `Code.ensure_loaded?/1` has to load
  # any module the suite has not touched yet. Every one of those loads serialises
  # through the single code server, so run concurrently this burst stalls whichever
  # process next needs a module — and an Oban worker blocked there is a worker holding
  # a checked-out DB connection. That is how the first version of this file reliably
  # timed out `ImportEnrollmentCsvTest`'s 5k-row smoke test at the 15s pool checkout.
  # In the sync phase nothing else is running, so the same sweep costs ~200ms and
  # bothers no one.
  use ExUnit.Case, async: false

  alias KlassHero.ProjectionSupervisor

  setup_all do
    # `use KlassHero.Shared.Projection` is what defines both of these, so exporting the
    # pair identifies a projection without the macro having to register itself — and
    # without this test encoding a naming convention the guard would then fail to police.
    {:ok, modules} = :application.get_key(:klass_hero, :modules)

    found =
      for module <- modules,
          Code.ensure_loaded?(module),
          function_exported?(module, :rebuild, 1),
          function_exported?(module, :topics, 0),
          do: module

    %{projection_modules: found}
  end

  test "every projection module is registered in projections/0", %{projection_modules: found} do
    unregistered = found -- ProjectionSupervisor.projections()

    assert unregistered == [],
           """
           Projection modules absent from ProjectionSupervisor.projections/0: \
           #{inspect(unregistered)}
           They are unsupervised, unrebuilt by the seeds, and invisible to the event
           consumer wiring test. Add them to `projections/0` in
           lib/klass_hero/projection_supervisor.ex.
           """
  end

  test "projections/0 names no module that has stopped being a projection", %{projection_modules: found} do
    stale = ProjectionSupervisor.projections() -- found

    assert stale == [],
           """
           ProjectionSupervisor.projections/0 names modules that are no longer \
           projections: #{inspect(stale)}
           Deleting a projection means deleting its entry here too — #1222 was a \
           dangling entry like this reaching priv/repo/seeds.exs.
           """
  end
end
