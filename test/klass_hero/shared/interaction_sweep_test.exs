defmodule KlassHero.Shared.InteractionSweepTest do
  @moduledoc """
  Stage 2 regression net: proves every DB repository context now drives its I/O
  through the `KlassHero.Shared.Interaction` envelope (emits the
  `[:klass_hero, :interaction, :stop]` telemetry event) rather than the bare
  `Tracing.span` macro or no observability at all.

  One representative zero-setup probe per context — a fresh-DB empty read whose
  native return is unchanged but which must now emit an interaction event. The
  per-repo behaviour-preservation net is each repository's own existing suite;
  this file only guards "the envelope is wired in", context by context.
  """

  # async: false — telemetry handlers are global; a concurrent module's
  # interaction events would otherwise arrive at this test's handler.
  use KlassHero.DataCase, async: false

  alias KlassHero.Shared.Adapters.Driven.Persistence.Repositories.ProcessedEventRepository

  setup do
    test_pid = self()
    ref = make_ref()

    :telemetry.attach_many(
      {__MODULE__, ref},
      [[:klass_hero, :interaction, :stop]],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end,
      %{}
    )

    on_exit(fn -> :telemetry.detach({__MODULE__, ref}) end)
    :ok
  end

  describe "every DB context drives I/O through the Interaction envelope" do
    # All seven domain contexts — Accounts, Family, Program Catalog, Participation, Enrollment,
    # Messaging, and Provider — have no probe here: the conventional-Phoenix flatten replaced the
    # per-adapter Interaction envelope with the seam-level `context_span` macro on writes (reads
    # stay bare), so their DB I/O no longer emits the `[:klass_hero, :interaction, :stop]` event
    # this sweep watches. Only the shared greenfield infra below still runs through the envelope.

    test "shared (greenfield) — ProcessedEventRepository.execute_atomically/3" do
      assert ProcessedEventRepository.execute_atomically(Ecto.UUID.generate(), "sweep-probe", fn -> :ok end) == :ok

      assert_receive {:telemetry, [:klass_hero, :interaction, :stop], _,
                      %{io_kind: :db, operation: :execute_atomically, status: :ok}}
    end
  end
end
