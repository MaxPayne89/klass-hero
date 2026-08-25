defmodule KlassHero.Shared.CompensatingWorkerRegistryTest do
  @moduledoc """
  Guards the registry against the two ways it goes silently wrong: a worker listed
  without the callback it promises, and a name that does not match what
  `oban_jobs.worker` actually stores — either of which makes the sweep skip a job
  while looking like it swept it.
  """

  use ExUnit.Case, async: true

  alias KlassHero.Shared.CompensatingWorkerRegistry

  describe "workers/0" do
    test "every registered worker implements the callback it is registered for" do
      # Iterates the registry, never the whole module list: loading every module to find
      # implementers starves the code server and surfaces as an unrelated DB pool timeout
      # (#1232).
      for worker <- CompensatingWorkerRegistry.workers() do
        Code.ensure_loaded!(worker)

        assert function_exported?(worker, :compensate, 2),
               "#{inspect(worker)} is registered for compensation sweeping but does not implement compensate/2"
      end
    end

    test "is not empty" do
      # A registry emptied by a bad merge would make every assertion above vacuous.
      refute CompensatingWorkerRegistry.workers() == []
    end
  end

  describe "worker_names/0" do
    # oban_jobs.worker holds "KlassHero.Foo", not "Elixir.KlassHero.Foo". A raw
    # Kernel.to_string/1 would produce the latter and the sweep's `worker in ^names`
    # filter would match nothing at all — a sweep that runs, reports success, and
    # compensates nothing.
    test "renders names the way Oban persists them" do
      for name <- CompensatingWorkerRegistry.worker_names() do
        # Oban stores the inspect/1 form; a bare to_string(Module) would prefix "Elixir."
        # and never match a persisted job row.
        refute String.starts_with?(name, "Elixir.")

        refute String.starts_with?(name, "Elixir."),
               "#{name} carries the Elixir. prefix that oban_jobs.worker does not store"
      end
    end

    test "round-trips back to the registered modules" do
      resolved =
        for name <- CompensatingWorkerRegistry.worker_names() do
          {:ok, module} = Oban.Worker.from_string(name)
          module
        end

      assert resolved == CompensatingWorkerRegistry.workers()
    end
  end
end
