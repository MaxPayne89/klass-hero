# Staged Credo checks — reported, never gating.
#
# These are third-party checks we intend to adopt but that still have a backlog on this
# tree. They are deliberately NOT in `.credo.exs`, because everything there runs through
# `.claude/hooks/credo.sh` on every single edit: a check with 155 open findings would fire
# on unrelated files, wake the session with noise, and teach us to skim past credo output.
# A gate nobody reads is worse than no gate.
#
# Run with `mix credo.backlog`. Counts below are the baseline measured when this landed —
# they exist so you can tell progress from drift.
#
# The ratchet: clear a check's backlog, then MOVE its entry into `.credo.exs`'s enabled
# list and delete it here. A check reaching zero and staying in this file is not adopted.
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
      },
      plugins: [],
      requires: [],
      strict: true,
      parse_timeout: 30_000,
      color: true,
      checks: %{
        enabled: [
          # 155 — `assert is_list(x)` / `refute is_nil(x)` where a pattern match would say
          # what the value should actually be. The largest backlog and the highest value:
          # this is the exact shape of #1416 and #1142.
          {Jump.CredoChecks.WeakAssertion, []},
          # 50 — an assign written but never read in that module's .ex or .heex. #1073 was
          # this bug reaching production as a page crash.
          {Jump.CredoChecks.UnusedLiveViewAssign, []},
          # 34 — tests introspecting socket assigns instead of asserting rendered behaviour.
          {Jump.CredoChecks.AvoidSocketAssignsInTest, []},
          # 24 — tests that never call application code. The check the article's author
          # wrote specifically to catch LLM-generated tests.
          {Jump.CredoChecks.VacuousTest, []},
          # 19 — `assert a == :x or b == :y`, which passes on either branch.
          {Jump.CredoChecks.ConditionalAssertion, []},
          # 16 — a phx-submit form with no id/phx-change cannot be rehydrated after a
          # reconnect or deploy, so the user silently loses what they typed.
          {Jump.CredoChecks.LiveViewFormCanBeRehydrated, []},
          # 13 — modules with iex> examples and no corresponding doctest call.
          {Jump.CredoChecks.DoctestIExExamples, []},
          # 10 — alias/import/require inside a function body.
          {Jump.CredoChecks.TopLevelAliasImportRequire, []},
          # 7 — explicit assert_receive timeouts, which pass locally and flake on CI.
          # See memory `main-suite-flake-baseline`: this repo already has a flake budget.
          {Jump.CredoChecks.AssertReceiveTimeout, min_assert_receive_timeout: 1_000, max_refute_receive_timeout: 100}
        ]
      }
    }
  ]
}
