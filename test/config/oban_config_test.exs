defmodule KlassHero.ObanConfigTest do
  @moduledoc """
  Guards two Oban plugin facts that regress silently.

  Neither raises, logs, nor fails a test when it breaks. A missing `Lifeline` presents as jobs
  sitting in `executing` in a table nobody watches; an over-eager `Pruner` presents as an empty
  `/oban` dashboard. Both are only discoverable by reading the config block itself.
  """

  use ExUnit.Case, async: true

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
  end

  # config/test.exs adds only `testing: :inline` and Config.Reader deep-merges, so the plugin list
  # read here is the one dev and prod actually run.
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
