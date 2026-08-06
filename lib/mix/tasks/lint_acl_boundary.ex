defmodule Mix.Tasks.LintAclBoundary do
  @shortdoc "Check that cross-context table reads stay visible in traces"
  @moduledoc """
  Enforces ADR 0015's call-site observability rule.

  A bounded context may query another context's table directly — ADR 0015 lists
  cycle-breaking direct table access as one of the four things that earns an ACL its
  place, and `.claude/rules/domain-architecture.md` allows the same read inline. What
  it may not do is make that hop invisible: *"Observability is preserved at the call
  site, not by the adapter."*

  So the rule is one line — **a file that reads another context's table must contain
  an `acl_span`** — and this task checks it.

  ## Ownership is derived, not configured

  Every table in the tree declares itself exactly once, via `schema "<table>"`. The
  context that owns a table is the context directory that declaration sits in, so the
  map needs no maintenance and cannot drift from the schemas. It also means a quoted
  string that is not a table name — `invite_family_ready_handler.ex` says `in
  "registered" status` in its moduledoc — is ignored for free rather than needing a
  pattern to exclude it.

  ## Granularity: one `acl_span` per reading function, not per table or per file

  A cross-context query frequently spans three tables and two foreign contexts.
  `family/…/acl/child_enrollment_acl.ex` joins `enrollments` and `programs` under a
  single `target: "enrollment"` — the `FROM` table's context — and that is the
  established shape. Requiring a span per foreign table would flag code that follows
  the precedent.

  Per *file* is too coarse in the other direction, and not hypothetically:
  `enrollment.ex` carries six `acl_span`s for its Family hops while its `programs`
  join went untraced for three weeks (#1274). A file-level check passes that file.

  So a reference counts as traced when an `acl_span` appears between it and its
  enclosing `def`/`defp` — which is where every span in the tree already sits, at the
  top of the function body.

  Text-based on purpose: this runs in the `quality` CI job, which must keep its
  `mix compile --warnings-as-errors` step first (see `.github/workflows/ci.yml`).

  ## Escape hatch

  A file-wide `# acl-boundary-lint-ignore: <reason>` comment exempts a file. Nothing
  in the tree uses it today — `admin/queries.ex` is a cross-cutting read surface that
  owns no tables, and it carries real spans rather than an exemption. It exists for a
  future read that genuinely cannot be traced.

  ## Usage

      mix lint_acl_boundary
  """
  use Mix.Task

  @contexts_dir "lib/klass_hero"

  # Quotes `schema "provider_programs"` in its own moduledoc, which would register a
  # phantom second owner for a table Provider already declares.
  @excluded_files ["read_table.ex"]

  @suppression_marker "acl-boundary-lint-ignore"

  @schema ~r/^\s*schema\s+"(?<table>\w+)"/m

  # The Ecto binding form — `from(p in "programs", ...)` and `join: p in "programs"`.
  # Schemaless queries are the only way to reach a foreign table without aliasing its
  # module, which is itself a boundary violation the boundary-checker agent covers.
  @table_reference ~r/\bin\s+"(?<table>\w+)"/

  @acl_span ~r/\bacl_span\b/

  @def ~r/^\s*defp?\s/m

  @impl true
  def run(_args) do
    violations = violations(@contexts_dir)

    if violations == [] do
      Mix.shell().info("ACL boundary lint passed — every cross-context table read is traced.")
    else
      Mix.shell().error("Untraced cross-context table reads:\n")

      Enum.each(violations, fn {file, message} ->
        Mix.shell().error("  #{file}: #{message}")
      end)

      Mix.shell().error("""

      See `docs/adr/0015-cross-context-reads-call-the-facade-directly.md`.
      Wrap the read so the hop stays visible in traces:

          use KlassHero.Shared.Tracing

          def my_read do
            acl_span source: "<this context>", target: "<owning context>" do
              # the query
            end
          end

      For a read that genuinely cannot be traced, add:

          # acl-boundary-lint-ignore: <why this hop is invisible>
      """)

      Mix.raise("ACL boundary lint failed — #{length(violations)} violation(s) found")
    end
  end

  @doc """
  Returns `[{file, message}]` for every untraced cross-context table read under
  `contexts_dir`.

  Takes the directory rather than hard-coding it so the test suite can drive the real
  globbing — and, because ownership is derived from the same tree, so a fixture can
  declare its own owners.
  """
  @spec violations(Path.t()) :: [{Path.t(), String.t()}]
  def violations(contexts_dir) do
    files =
      contexts_dir
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.reject(&(Path.basename(&1) in @excluded_files))
      |> Enum.map(&{&1, File.read!(&1)})

    owners = owners(files, contexts_dir)

    files
    |> Enum.reject(fn {_file, content} -> exempt?(content) end)
    |> Enum.flat_map(fn {file, content} ->
      case foreign_reads(content, owners, context_of(file, contexts_dir)) do
        [] -> []
        reads -> [{file, message(reads)}]
      end
    end)
  end

  # File-wide, unlike the span check: a file can hold several reads and these violations
  # have no single offending line for a marker to sit beside — same reasoning as
  # `mix lint_read_tables`.
  defp exempt?(content), do: String.contains?(content, @suppression_marker)

  # A table declared twice would resolve to whichever context sorts last. Only
  # `read_table.ex` ever did that, by quoting an example in its moduledoc, and it is
  # excluded above — so in practice every table has exactly one owner.
  defp owners(files, contexts_dir) do
    for {file, content} <- files,
        [_full, table] <- Regex.scan(@schema, content),
        into: %{},
        do: {table, context_of(file, contexts_dir)}
  end

  defp foreign_reads(content, owners, context) do
    defs = offsets(content, @def)
    spans = offsets(content, @acl_span)

    for {offset, table} <- table_references(content),
        owner = owners[table],
        owner != nil and owner != context,
        not traced?(offset, defs, spans),
        uniq: true,
        do: {owner, table}
  end

  defp table_references(content) do
    for [_full, {at, len}] <- Regex.scan(@table_reference, content, return: :index),
        do: {at, binary_part(content, at, len)}
  end

  # Traced when a span opens after the enclosing function head and before the reference.
  # A reference above the first `def` has no enclosing function, so offset 0 stands in.
  defp traced?(offset, defs, spans) do
    enclosing_def = defs |> Enum.take_while(&(&1 < offset)) |> List.last() || 0

    Enum.any?(spans, &(&1 > enclosing_def and &1 < offset))
  end

  defp offsets(content, regex) do
    for [{at, _len}] <- Regex.scan(regex, content, return: :index), do: at
  end

  defp message(reads) do
    reads
    |> Enum.sort()
    |> Enum.map_join(", ", fn {owner, table} -> "#{owner}'s `#{table}`" end)
    |> then(
      &("reads #{&1} with no acl_span — ADR 0015 keeps the cross-context hop visible at the " <>
          "call site, not in the adapter")
    )
  end

  # `lib/klass_hero/enrollment.ex` and `lib/klass_hero/enrollment/**/*.ex` are both
  # Enrollment; the facade is a file where every other context is a directory.
  defp context_of(file, contexts_dir) do
    file
    |> Path.relative_to(contexts_dir)
    |> Path.split()
    |> hd()
    |> Path.basename(".ex")
  end
end
