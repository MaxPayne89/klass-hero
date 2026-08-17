defmodule Mix.Tasks.LintReadTables do
  @shortdoc "Check the projection read-table convention (declaration, no changeset, placement)"
  @moduledoc """
  Enforces the projection read-table convention documented in
  `.claude/rules/domain-architecture.md` ("CQRS Read Models").

  A projection read table declares itself with `use KlassHero.Shared.ReadTable`.
  Three rules follow, one check each:

  * **Undeclared** — a context-root Ecto schema with no changeset and no marker is
    neither an entity (entities validate at the DB boundary, so they have a
    changeset) nor a declared read table. Either it is a read table and should say
    so, or it needs a changeset, or it is a legitimate third thing and needs the
    escape hatch below.
  * **Changeset on a read table** — the projection is the only writer, so a
    changeset means something else writes the table.
  * **Misplaced** — a read table lives at the context root, beside the entities,
    not inside `adapters/`.

  Text-based on purpose: this runs in the `quality` CI job, which must keep its
  `mix compile --warnings-as-errors` step first (see `.github/workflows/ci.yml`).

  That is also this task's limit. The fourth read-table rule — **no length caps**,
  see `KlassHero.Shared.ReadTable` — is invisible here, because `field :url, :string`
  reads identically whether the column is `varchar(255)` or `text`. It is enforced
  against the database by `test/klass_hero/shared/read_table_column_types_test.exs`.

  ## Escape hatch

  A file-wide `# read-table-lint-ignore: <reason>` comment exempts a file. These
  violations are module-level, so unlike `mix lint_typography` there is no
  offending line for the marker to sit beside.

  ## Usage

      mix lint_read_tables
  """
  use Mix.Task

  @contexts_dir "lib/klass_hero"

  # The module that defines the marker quotes it in its own moduledoc.
  @excluded_files ["read_table.ex"]

  @suppression_marker "read-table-lint-ignore"

  @marker ~r/^\s*use\s+KlassHero\.Shared\.ReadTable\b/m
  @schema ~r/^\s*use\s+Ecto\.Schema\b/m

  # Substring, not literal: only 13 of 77 changeset clauses in the tree are named
  # plain `changeset` — the rest are create_changeset, admin_changeset, etc.
  @changeset ~r/^\s*def\s+\w*changeset\w*\(/m

  @impl true
  def run(_args) do
    violations = violations(@contexts_dir)

    if violations == [] do
      Mix.shell().info("Read-table lint passed — projection read tables follow the convention.")
    else
      Mix.shell().error("Projection read-table convention violated:\n")

      Enum.each(violations, fn {file, message} ->
        Mix.shell().error("  #{file}: #{message}")
      end)

      Mix.shell().error("""

      See `.claude/rules/domain-architecture.md` ("CQRS Read Models").
      To exempt a file that is legitimately neither an entity nor a read table, add:

          # read-table-lint-ignore: <why this schema has no changeset>
      """)

      Mix.raise("Read-table lint failed — #{length(violations)} violation(s) found")
    end
  end

  @doc """
  Returns `[{file, message}]` for every violation under `contexts_dir`.

  Takes the directory rather than hard-coding it so the test suite can drive the
  real globbing — including the depth-1 rule below — against a fixture tree.
  """
  @spec violations(Path.t()) :: [{Path.t(), String.t()}]
  def violations(contexts_dir) do
    # `**` matches zero or more directories, so this also covers the context facades.
    all = Path.wildcard(Path.join(contexts_dir, "**/*.ex"))

    # Rule (a) is deliberately depth-1 only. Recursively, it would also flag the
    # changeset-less infrastructure schemas under
    # shared/adapters/driven/persistence/schemas/ — rows there are built from struct
    # literals and written with `insert_all`, so they are neither entities nor read
    # tables, and exempting each would make the escape hatch the common case.
    context_roots = MapSet.new(Path.wildcard(Path.join(contexts_dir, "*/*.ex")))

    all
    |> Enum.reject(&(Path.basename(&1) in @excluded_files))
    |> Enum.map(&{&1, File.read!(&1)})
    |> Enum.reject(fn {_file, content} -> String.contains?(content, @suppression_marker) end)
    |> Enum.flat_map(fn {file, content} ->
      case violation(file, content, context_roots) do
        nil -> []
        message -> [{file, message}]
      end
    end)
  end

  defp violation(file, content, context_roots) do
    facts = %{
      marker?: Regex.match?(@marker, content),
      changeset?: Regex.match?(@changeset, content),
      schema?: Regex.match?(@schema, content),
      context_root?: MapSet.member?(context_roots, file)
    }

    rules = [&changeset_on_read_table/1, &misplaced_read_table/1, &undeclared_schema/1]

    Enum.find_value(rules, & &1.(facts))
  end

  defp changeset_on_read_table(%{marker?: true, changeset?: true}) do
    "declared a read table but defines a changeset — the projection owns every write, " <>
      "so drop the changeset or drop the `use KlassHero.Shared.ReadTable`"
  end

  defp changeset_on_read_table(_facts), do: nil

  defp misplaced_read_table(%{marker?: true, context_root?: false}) do
    "declared a read table but is not at a context root — move it to lib/klass_hero/<context>/"
  end

  defp misplaced_read_table(_facts), do: nil

  defp undeclared_schema(%{context_root?: true, schema?: true, marker?: false, changeset?: false}) do
    "context-root Ecto schema with no changeset — add `use KlassHero.Shared.ReadTable` if a " <>
      "projection maintains it, add a changeset if it is an entity, or add the ignore comment"
  end

  defp undeclared_schema(_facts), do: nil
end
