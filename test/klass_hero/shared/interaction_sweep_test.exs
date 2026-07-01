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

  alias KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.ConversationSummariesRepository
  alias KlassHero.Provider.Adapters.Driven.Persistence.Repositories.SessionStatsRepository
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
    # Accounts, Family, Program Catalog, Participation, and Enrollment have no probe here:
    # the conventional-Phoenix flatten replaced the per-adapter Interaction envelope with the
    # seam-level `context_span` macro, which emits OTel spans (not the
    # `[:klass_hero, :interaction, :stop]` event this sweep watches).

    test "provider (greenfield read model) — SessionStatsRepository.list_for_provider/1" do
      assert SessionStatsRepository.list_for_provider(Ecto.UUID.generate()) == []

      assert_receive {:telemetry, [:klass_hero, :interaction, :stop], _,
                      %{io_kind: :db, operation: :list_for_provider, status: :ok}}
    end

    test "messaging — ConversationSummariesRepository.get_total_unread_count/1" do
      assert ConversationSummariesRepository.get_total_unread_count(Ecto.UUID.generate()) == 0

      assert_receive {:telemetry, [:klass_hero, :interaction, :stop], _,
                      %{io_kind: :db, operation: :get_total_unread_count, status: :ok}}
    end

    test "shared (greenfield) — ProcessedEventRepository.mark_processed/2" do
      assert ProcessedEventRepository.mark_processed(Ecto.UUID.generate(), "sweep-probe") == :ok

      assert_receive {:telemetry, [:klass_hero, :interaction, :stop], _,
                      %{io_kind: :db, operation: :mark_processed, status: :ok}}
    end
  end
end
