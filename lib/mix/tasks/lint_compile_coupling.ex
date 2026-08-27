defmodule Mix.Tasks.LintCompileCoupling do
  @shortdoc "Fail if compile-time coupling grows beyond the recorded ceiling"
  @moduledoc """
  Wraps `mix xref graph --label compile-connected` with a ceiling on the count.

  Keeps a runtime dependency from silently becoming a compile-time one, which
  balloons recompiles across a seven-context app.

  ## Why this is a task and not a line in two places

  The ceiling used to be written twice — in `mix.exs`'s `precommit` alias and in
  `.github/workflows/ci.yml` — and the two drifted the first time it moved:
  `precommit` passed locally at the new number while CI still failed at the old
  one. Every other check in that CI job is a `mix lint_*` task for exactly this
  reason. One number, one place, both callers.

  ## The ceiling is a ratchet, not an aspiration

  It is the count the tree had when the gate landed, and nearly all of it is
  inherent `use`-macro coupling: Backpex admin LiveViews to their schemas,
  messaging LiveViews to their shared helper, Oban workers to `TracedWorker`.
  Driving it to zero is not the goal; noticing the next one is. Lower it whenever
  a refactor earns it, and raise it only after reading the printed graph and
  confirming the new edge is that same inherent kind.

  ## Usage

      mix lint_compile_coupling
  """
  use Mix.Task

  # 34 as of #1071: NewMessageEmailWorker -> RateLimitedEmailWorker/TracedWorker
  # and NewMessageEmailNotifier -> Shared.Interaction. Both are the inherent kind
  # above, identical to the four email workers already counted — no runtime
  # dependency was converted into a compile-time one.
  @ceiling 34

  @impl true
  def run(_args) do
    # Runs xref in a subprocess so its stdout can be swallowed: the full graph is
    # printed even on success, which is ~60 lines of noise in every CI log. The
    # failure message goes to stderr and is left alone, so it still surfaces.
    {_graph, status} =
      System.cmd(
        "mix",
        ["xref", "graph", "--label", "compile-connected", "--fail-above", to_string(@ceiling)],
        into: "",
        stderr_to_stdout: false
      )

    if status == 0 do
      Mix.shell().info("Compile coupling lint passed — at or below #{@ceiling} references.")
    else
      Mix.raise("""
      Compile-time coupling grew past #{@ceiling}.

      Run `mix xref graph --label compile-connected` to see what is connected. If
      the new edge is inherent `use`-macro coupling, raise @ceiling in
      lib/mix/tasks/lint_compile_coupling.ex and record why. If a runtime
      dependency became compile-time, fix that instead of the number.
      """)
    end
  end
end
