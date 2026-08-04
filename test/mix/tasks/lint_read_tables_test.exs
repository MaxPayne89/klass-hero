defmodule Mix.Tasks.LintReadTablesTest do
  @moduledoc """
  Drives `Mix.Tasks.LintReadTables.violations/1` against a fixture tree.

  The tree is the point: the depth-1 scoping of rule (a) and the placement rule are
  properties of the globbing, not of the per-file classification, so a test that only
  fed strings to a matcher would miss both.
  """

  use ExUnit.Case, async: true

  alias Mix.Tasks.LintReadTables

  @marker "use KlassHero.Shared.ReadTable"

  describe "violations/1" do
    @tag :tmp_dir
    test "passes a tree where every schema is an entity or a declared read table", %{tmp_dir: dir} do
      write(dir, "provider/provider_program.ex", schema(marker: true))
      write(dir, "provider/staff_member.ex", schema(changeset: "create_changeset"))
      write(dir, "provider/adapters/driven/projections/provider_programs.ex", plain_module())

      assert LintReadTables.violations(dir) == []
    end

    @tag :tmp_dir
    test "flags a read table that defines a changeset", %{tmp_dir: dir} do
      write(dir, "provider/provider_program.ex", schema(marker: true, changeset: "changeset"))

      assert [{path, message}] = LintReadTables.violations(dir)
      assert Path.basename(path) == "provider_program.ex"
      assert message =~ "defines a changeset"
    end

    @tag :tmp_dir
    test "flags a read table declared outside the context root", %{tmp_dir: dir} do
      write(dir, "provider/adapters/driven/projections/session_stats.ex", schema(marker: true))

      assert [{path, message}] = LintReadTables.violations(dir)
      assert path =~ "projections/session_stats.ex"
      assert message =~ "not at a context root"
    end

    @tag :tmp_dir
    test "flags a context-root schema that is neither an entity nor a declared read table", %{tmp_dir: dir} do
      write(dir, "accounts/user_token.ex", schema([]))

      assert [{path, message}] = LintReadTables.violations(dir)
      assert Path.basename(path) == "user_token.ex"
      assert message =~ "no changeset"
    end

    @tag :tmp_dir
    test "the ignore comment exempts a file", %{tmp_dir: dir} do
      write(dir, "accounts/user_token.ex", """
      # read-table-lint-ignore: tokens are built from struct literals
      #{schema([])}
      """)

      assert LintReadTables.violations(dir) == []
    end

    # Rule (a) is depth-1 by design. A recursive scan would flag the changeset-less
    # infrastructure schemas under shared/adapters/driven/persistence/schemas/.
    @tag :tmp_dir
    test "a changeset-less schema below the context root is not a rule (a) violation", %{tmp_dir: dir} do
      write(dir, "shared/adapters/driven/persistence/schemas/processed_event.ex", schema([]))

      assert LintReadTables.violations(dir) == []
    end

    # The module defining the marker quotes it on its own line in a moduledoc code
    # block, which the line-anchored marker regex matches. The paired assertion is
    # what makes this non-vacuous: identical content under any other basename IS a
    # violation, so the exclusion is doing the work rather than the regex missing.
    @tag :tmp_dir
    test "read_table.ex is excluded so its own usage example is not read as a declaration", %{tmp_dir: dir} do
      write(dir, "shared/nested/read_table.ex", marker_in_moduledoc())
      assert LintReadTables.violations(dir) == []

      write(dir, "shared/nested/impostor.ex", marker_in_moduledoc())
      assert [{path, _message}] = LintReadTables.violations(dir)
      assert Path.basename(path) == "impostor.ex"
    end

    test "the real tree satisfies the convention" do
      assert LintReadTables.violations("lib/klass_hero") == []
    end

    @tag :tmp_dir
    test "recognises changeset clauses whose names are not plain `changeset`", %{tmp_dir: dir} do
      for name <- ~w(create_changeset admin_changeset anonymize_changeset invitation_changeset) do
        write(dir, "provider/#{name}_entity.ex", schema(changeset: name))
      end

      assert LintReadTables.violations(dir) == [],
             "a *_changeset/2 clause must count as a changeset — only 13 of 77 in the tree are named plain `changeset`"
    end
  end

  defp write(dir, relative_path, content) do
    path = Path.join(dir, relative_path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
  end

  defp schema(opts) do
    marker = if opts[:marker], do: "  #{@marker}\n", else: ""

    changeset =
      case opts[:changeset] do
        nil -> ""
        name -> "\n  def #{name}(struct, attrs) do\n    cast(struct, attrs, [:name])\n  end\n"
      end

    """
    defmodule KlassHero.Fixture do
      use Ecto.Schema
    #{marker}
      schema "fixtures" do
        field :name, :string
      end
    #{changeset}end
    """
  end

  # Mirrors how lib/klass_hero/shared/read_table.ex quotes the marker: own line,
  # indented inside a moduledoc code block — which the marker regex matches.
  defp marker_in_moduledoc do
    """
    defmodule KlassHero.Fixture.Marker do
      @moduledoc \"\"\"
          defmodule Example do
            use Ecto.Schema
            #{@marker}
          end
      \"\"\"
    end
    """
  end

  defp plain_module do
    """
    defmodule KlassHero.Fixture.Projection do
      use KlassHero.Shared.Projection, topics: []
    end
    """
  end
end
