defmodule KlassHero.ObanConfigTest do
  @moduledoc """
  Guards two Oban plugin facts that regress silently.

  Neither raises, logs, nor fails a test when it breaks. A missing `Lifeline` presents as jobs
  sitting in `executing` in a table nobody watches; an over-eager `Pruner` presents as an empty
  `/oban` dashboard. Both are only discoverable by reading the config block itself.
  """

  use ExUnit.Case, async: true

  alias KlassHero.Shared.Adapters.Driven.Workers.CompensationSweepWorker

  describe "oban plugins" do
    # A machine going away mid-job leaves that job `executing` with nothing to move it back.
    # fly.toml sets auto_stop_machines = "suspend" and min_machines_running = 0, so machines
    # disappearing is routine rather than exceptional.
    test "rescues jobs orphaned when a machine goes away" do
      assert plugin_opts(Oban.Plugins.Lifeline),
             "Oban.Plugins.Lifeline is missing — orphaned jobs stay `executing` forever (#1191)"
    end

    # Pruner defaults to max_age: 60 *seconds*, which deletes a permanently-failed critical event's
    # row before anyone can open the dashboard. EventDeliveryWorker retries for roughly 4.5 hours, so
    # the row has to outlive that span by enough to be triaged the next morning.
    test "keeps finished job rows long enough to triage" do
      opts = plugin_opts(Oban.Plugins.Pruner)

      assert opts, "Oban.Plugins.Pruner is missing"

      assert Keyword.get(opts, :max_age, 60) >= 86_400,
             "Pruner max_age is under a day — discarded jobs vanish before triage"
    end

    # The sweep is the only thing that compensates a job which died without running its
    # own gate. Dropped from the crontab it fails silently: nothing errors, invites and
    # emails simply keep looking pending after the job that owned them is gone.
    test "sweeps discarded jobs for uncompensated work" do
      assert {_expression, CompensationSweepWorker} = crontab_entry(CompensationSweepWorker),
             "CompensationSweepWorker is missing from the crontab — jobs that die without " <>
               "running their compensation gate are never reconciled (#1234)"
    end

    # The sweep only ever sees a discarded job while its row survives, so the Pruner
    # window is the sweep's window. Guarded together because tightening one silently
    # shortens the other.
    test "prunes no faster than the sweep can reach a discarded job" do
      {expression, _worker} = crontab_entry(CompensationSweepWorker)
      max_age = Oban.Plugins.Pruner |> plugin_opts() |> Keyword.get(:max_age, 60)

      assert max_age > 3600,
             "Pruner max_age (#{max_age}s) leaves too little room for the sweep at #{expression}"
    end

    # The other end of the same coupling. A marker exists to stop the sweep reaching a job it
    # already compensated; delete it while that job row survives and the sweep compensates the
    # job a second time. Neither side can see the other — the retention is a module attribute,
    # the window is config — so this is the only place the two are compared.
    test "keeps compensation markers longer than the job rows they guard" do
      retention = CompensationSweepWorker.job_compensation_retention_days() * 86_400
      max_age = Oban.Plugins.Pruner |> plugin_opts() |> Keyword.get(:max_age, 60)

      assert retention > max_age,
             "job_compensations retention (#{retention}s) is shorter than the Pruner window " <>
               "(#{max_age}s) — a marker can be deleted while its job row is still discardable, " <>
               "and the next sweep compensates that job twice"
    end
  end

  # config/test.exs adds only `testing: :inline` and Config.Reader deep-merges, so the plugin list
  # read here is the one dev and prod actually run.
  defp crontab_entry(worker) do
    Oban.Plugins.Cron
    |> plugin_opts()
    |> Keyword.get(:crontab, [])
    |> Enum.find(fn {_expression, scheduled} -> scheduled == worker end)
  end

  defp plugin_opts(module) do
    :klass_hero
    |> Application.fetch_env!(Oban)
    |> Keyword.fetch!(:plugins)
    |> Enum.find_value(fn
      ^module -> []
      {^module, opts} -> opts
      _other -> nil
    end)
  end
end
