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
      assert service_opts(:lifeline),
             "Oban's :lifeline service is missing or disabled — orphaned jobs stay `executing` " <>
               "forever (#1191)"
    end

    # Pruner defaults to max_age: 60 *seconds*, which deletes a permanently-failed critical event's
    # row before anyone can open the dashboard. EventDeliveryWorker retries for roughly 4.5 hours, so
    # the row has to outlive that span by enough to be triaged the next morning.
    test "keeps finished job rows long enough to triage" do
      assert service_opts(:pruner), "Oban's :pruner service is missing or disabled"

      assert pruner_max_age_seconds() >= 86_400,
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
      max_age = pruner_max_age_seconds()

      assert max_age > 3600,
             "Pruner max_age (#{max_age}s) leaves too little room for the sweep at #{expression}"
    end

    # The other end of the same coupling. A marker exists to stop the sweep reaching a job it
    # already compensated; delete it while that job row survives and the sweep compensates the
    # job a second time. Neither side can see the other — the retention is a module attribute,
    # the window is config — so this is the only place the two are compared.
    test "keeps compensation markers longer than the job rows they guard" do
      retention = CompensationSweepWorker.job_compensation_retention_days() * 86_400
      max_age = pruner_max_age_seconds()

      assert retention > max_age,
             "job_compensations retention (#{retention}s) is shorter than the Pruner window " <>
               "(#{max_age}s) — a marker can be deleted while its job row is still discardable, " <>
               "and the next sweep compensates that job twice"
    end
  end

  # config/test.exs adds only `testing: :inline` and Config.Reader deep-merges, so the config
  # read here is the one dev and prod actually run.
  defp crontab_entry(worker) do
    (service_opts(:cron) || [])
    |> Keyword.get(:crontab, [])
    |> Enum.find(fn {_expression, scheduled} -> scheduled == worker end)
  end

  # Oban 2.24 replaced the `plugins:` list with a top-level key per service, so these are looked
  # up by service key rather than found by plugin module.
  #
  # Returns the option list when the service is configured — `[]` counts, since it means "on with
  # defaults" and is truthy — and nil when the key is absent or explicitly `false`. The nil is
  # load-bearing: a helper returning `[]` for a missing service would make `assert
  # service_opts(:lifeline)` pass whether or not Lifeline is configured at all.
  defp service_opts(key) when key in [:pruner, :lifeline, :cron] do
    :klass_hero
    |> Application.fetch_env!(Oban)
    |> Keyword.get(key)
    |> case do
      nil -> nil
      false -> nil
      opts when is_list(opts) -> opts
      module when is_atom(module) -> []
    end
  end

  defp pruner_max_age_seconds do
    :pruner
    |> service_opts()
    |> Kernel.||([])
    |> Keyword.get(:max_age, 60)
    |> to_seconds()
  end

  # The config may state max_age either way; both are first-class in Oban 2.24, and these tests
  # compare it against second-denominated windows on the sweep side.
  defp to_seconds(seconds) when is_integer(seconds), do: seconds
  defp to_seconds({count, :second}), do: count
  defp to_seconds({count, :seconds}), do: count
  defp to_seconds({count, :minute}), do: count * 60
  defp to_seconds({count, :minutes}), do: count * 60
  defp to_seconds({count, :hour}), do: count * 3600
  defp to_seconds({count, :hours}), do: count * 3600
  defp to_seconds({count, :day}), do: count * 86_400
  defp to_seconds({count, :days}), do: count * 86_400
end
