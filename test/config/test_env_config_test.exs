defmodule KlassHero.TestEnvConfigTest do
  @moduledoc """
  Guards the test-env HTTP endpoint configuration itself.

  Two facts about `config/test.exs` are easy to break silently and expensive to debug,
  because both fail as an `:eaddrinuse` or a connection refusal that names neither the
  config line nor the cause.
  """

  use ExUnit.Case, async: true

  # credo:disable-for-this-file Jump.CredoChecks.VacuousTest
  # Every test here asserts configuration rather than behaviour — that is the point of
  # the file. Both guards exist because a config drift broke the suite once already.

  describe "test endpoint binding" do
    # Only the Wallaby e2e suite drives a real browser against a real socket; every other
    # test reaches the endpoint through Plug/LiveView test helpers. Binding unconditionally
    # made a single global port (4002) a prerequisite for the whole suite, so one unrelated
    # process — another worktree, or another project entirely — blocked every test run.
    test "binds an HTTP socket only when running the e2e suite" do
      e2e? = System.get_env("WALLABY_E2E") == "true"

      assert Application.get_env(:klass_hero, KlassHeroWeb.Endpoint)[:server] == e2e?
    end

    # The endpoint port and Wallaby's base_url are two separate config entries that must
    # agree. Changing one alone breaks e2e with a connection error pointing at neither.
    test "wallaby drives the same port the endpoint binds" do
      endpoint_port = Application.get_env(:klass_hero, KlassHeroWeb.Endpoint)[:http][:port]
      %URI{port: base_url_port} = URI.parse(Application.get_env(:wallaby, :base_url))

      assert base_url_port == endpoint_port,
             "wallaby base_url port #{base_url_port} != endpoint port #{endpoint_port}"
    end
  end
end
