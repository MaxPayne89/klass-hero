defmodule Mix.Tasks.LintDocRefs do
  @shortdoc "Check that file paths and modules cited in agent-facing docs still exist"
  @moduledoc """
  Verifies that every repo-rooted file path and `KlassHero.*` module named in our
  agent-facing documentation still exists.

  These docs are load-bearing in a way ordinary prose is not: `CLAUDE.md`,
  `.claude/rules/*.md` and `.claude/agents/*.md` are read into context and acted on.
  A rule citing a module that was renamed two refactors ago does not merely go stale
  — it actively produces wrong work, and `.claude/agents/*.md` specs that drifted
  from the architecture emitted false review findings (#1255). That is drift
  degrading the very layer meant to catch drift, so it gets a mechanical gate.

  ## What it checks

  Only backticked tokens, which keeps prose out of scope:

    * paths — a backticked token beginning with a real top-level directory
      (`lib/`, `test/`, `docs/`, …). Requiring the prefix is what keeps relative
      fragments like `provider/staff_member.ex` and URL bits like `/pull/` out.
    * modules — a token matching `KlassHero*.Foo.Bar`, resolved by scanning the tree
      for its `defmodule`. Deliberately not `Code.ensure_loaded?/1`: this task runs
      in `:dev`, where every `test/support` module (`KlassHero.DataCase`) would look
      missing.

  Tokens containing `<`, `*`, `{`, `$` or `..` are illustrative placeholders
  (`lib/klass_hero/<context>/`) and are skipped.

  ## What it does not check

  `docs/adr/` is excluded. An ADR is an immutable record of a decision, so it cites
  the structure it replaced *on purpose* — ADR-0018 naming `adapters/driven/` is the
  document doing its job, not a stale reference. Editing ADRs to satisfy a linter
  would destroy the history they exist to keep.

  And a reference can be well-formed yet completely wrong. This catches dangling
  references only; whether a rule still describes what we do stays a human call.

  Waive with `doc-refs-lint-ignore`. The marker covers its own line and the next
  block of content, ending at the blank line that closes it — so one comment above a
  table of worked examples waives the whole table rather than needing a marker per
  row. It deliberately survives the blank line that markdown requires between an
  HTML comment and the table it introduces.

  ## Usage

      mix lint_doc_refs
  """
  use Mix.Task

  @doc_globs [
    "CLAUDE.md",
    "CONTEXT.md",
    "DESIGN.md",
    ".claude/rules/*.md",
    ".claude/agents/*.md",
    ".claude/skills/*/SKILL.md",
    "docs/agents/*.md",
    "docs/runbooks/*.md"
  ]

  @source_globs ["lib/**/*.ex", "priv/**/*.ex", "test/**/*.ex", "test/**/*.exs"]

  @path_prefixes ~w(lib/ test/ priv/ config/ assets/ bin/ docs/ .claude/ .github/)

  @suppression_marker "doc-refs-lint-ignore"
  @placeholder ~r/[<>*{}$]|\.\./
  @backticked ~r/`([^`\n]+)`/
  @path_like ~r|^[\w./-]+$|
  @has_extension ~r/\.[a-z]{1,5}$/
  @module_like ~r/^KlassHero[A-Za-z]*(\.[A-Z][A-Za-z0-9_]*)+$/
  # Named `_re` rather than `@defmodule`: Quokka's ModuleDirectives style crashes on an
  # attribute with that name (Quokka.Zipper.rightmost(nil)), printing a stack trace on
  # every `mix format` of this file. Non-fatal, but noise in precommit and the edit hook.
  @defmodule_re ~r/^\s*defmodule\s+([A-Za-z0-9_.]+)\s+do/m

  @impl true
  def run(_args) do
    modules = defined_modules()

    violations =
      @doc_globs
      |> Enum.flat_map(&Path.wildcard/1)
      |> Enum.flat_map(&check_file(&1, modules))

    if violations == [] do
      Mix.shell().info("Doc refs lint passed — every cited path and module resolves.")
    else
      Mix.shell().error(
        "Docs cite things that no longer exist. Update the doc, or waive the line " <>
          "with `#{@suppression_marker}`:\n"
      )

      Enum.each(violations, fn {file, line_num, kind, token} ->
        Mix.shell().error("  #{file}:#{line_num}: missing #{kind} `#{token}`")
      end)

      Mix.raise("Doc refs lint failed — #{length(violations)} dangling reference(s) found")
    end
  end

  # One pass over the tree, so a doc citing 200 modules still costs a single read
  # per source file rather than a grep per citation.
  defp defined_modules do
    @source_globs
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.flat_map(fn file ->
      @defmodule_re
      |> Regex.scan(File.read!(file), capture: :all_but_first)
      |> List.flatten()
    end)
    |> MapSet.new()
  end

  defp check_file(file, modules) do
    lines =
      file
      |> File.read!()
      |> String.split("\n")

    {_line_num, _suppressing?, violations} =
      Enum.reduce(lines, {1, :off, []}, fn line, {line_num, suppressing?, acc} ->
        suppressing? = advance(line, suppressing?)

        acc =
          if suppressing? == :off do
            line
            |> dangling_refs(modules)
            |> Enum.reduce(acc, fn {kind, token}, inner ->
              [{file, line_num, kind, token} | inner]
            end)
          else
            acc
          end

        {line_num + 1, suppressing?, acc}
      end)

    Enum.reverse(violations)
  end

  # :armed — marker seen, waiting for the block to start (blank lines don't end it).
  # :in_block — inside the waived block; the next blank line closes it.
  defp advance(line, state) do
    blank? = String.trim(line) == ""

    cond do
      String.contains?(line, @suppression_marker) -> :armed
      state == :armed and blank? -> :armed
      state == :armed -> :in_block
      state == :in_block and blank? -> :off
      true -> state
    end
  end

  defp dangling_refs(line, modules) do
    @backticked
    |> Regex.scan(line, capture: :all_but_first)
    |> List.flatten()
    |> Enum.reject(&placeholder?/1)
    |> Enum.flat_map(&classify/1)
    |> Enum.reject(&resolves?(&1, modules))
  end

  # `KlassHero.B` and `lib/x/y.ex` are stand-ins in a worked example, not references.
  # A single-character segment is the tell: no real module or directory here has one.
  defp placeholder?(token) do
    Regex.match?(@placeholder, token) or
      token
      |> String.split(["/", "."])
      |> Enum.any?(&(String.length(&1) == 1))
  end

  defp classify(token) do
    cond do
      Regex.match?(@module_like, token) -> [{:module, token}]
      path?(token) -> [{:path, token}]
      true -> []
    end
  end

  defp path?(token) do
    String.starts_with?(token, @path_prefixes) and Regex.match?(@path_like, token) and
      (String.ends_with?(token, "/") or Regex.match?(@has_extension, token))
  end

  defp resolves?({:path, token}, _modules), do: File.exists?(String.trim_trailing(token, "/"))
  defp resolves?({:module, token}, modules), do: MapSet.member?(modules, token)
end
