defmodule Mix.Tasks.LintAclBoundaryTest do
  @moduledoc """
  Drives `Mix.Tasks.LintAclBoundary.violations/1` against a fixture tree.

  The tree is the point twice over: table ownership is *derived* from the
  `schema "..."` declarations found under the same directory, so a test that fed
  strings to a matcher could not express "this table belongs to that context" at
  all — and the context of a file is a property of its path.
  """

  use ExUnit.Case, async: true

  alias Mix.Tasks.LintAclBoundary

  describe "violations/1" do
    @tag :tmp_dir
    test "flags a foreign table read with no acl_span", %{tmp_dir: dir} do
      write(dir, "program_catalog/program.ex", schema("programs"))
      write(dir, "enrollment.ex", query_over("programs"))

      assert [{path, message}] = LintAclBoundary.violations(dir)
      assert Path.basename(path) == "enrollment.ex"
      assert message =~ "program_catalog's `programs`"
      assert message =~ "acl_span"
    end

    # One behaviour — classifying a quoted name in a query — under the four inputs that
    # decide it. Only the first is a violation; the other three are the ways a match on
    # `in "..."` legitimately means nothing.
    @tag :tmp_dir
    test "classifies a quoted table reference", %{tmp_dir: dir} do
      cases = [
        {"a foreign table with no span", "enrollment", query_over("programs"), 1},
        {"the context's own table", "program_catalog", query_over("programs"), 0},
        {"a foreign table inside an acl_span", "enrollment", traced_query_over("programs"), 0},
        {"a quoted word that is not a table", "enrollment", query_over("registered"), 0}
      ]

      for {label, context, content, expected} <- cases do
        case_dir = Path.join(dir, String.replace(label, " ", "-"))
        write(case_dir, "program_catalog/program.ex", schema("programs"))
        write(case_dir, "#{context}/reader.ex", content)

        assert length(LintAclBoundary.violations(case_dir)) == expected,
               "#{label}: expected #{expected} violation(s)"
      end
    end

    @tag :tmp_dir
    test "names every foreign table a file reads", %{tmp_dir: dir} do
      write(dir, "enrollment/enrollment.ex", schema("enrollments"))
      write(dir, "family/child.ex", schema("children"))
      write(dir, "messaging/reader.ex", query_over("enrollments", "children"))

      assert [{_path, message}] = LintAclBoundary.violations(dir)
      assert message =~ "enrollment's `enrollments`"
      assert message =~ "family's `children`"
    end

    @tag :tmp_dir
    test "the ignore comment exempts a file", %{tmp_dir: dir} do
      write(dir, "program_catalog/program.ex", schema("programs"))

      write(dir, "enrollment/reader.ex", """
      # acl-boundary-lint-ignore: this read cannot be traced because <reason>
      #{query_over("programs")}
      """)

      assert LintAclBoundary.violations(dir) == []
    end

    # read_table.ex quotes `schema "provider_session_details"` in its own moduledoc. Without the
    # exclusion that quote registers Shared as the owner of a table Provider declares, and
    # every Provider read of its OWN table starts reading as cross-context. The paired
    # assertion is what makes this non-vacuous: identical content under any other basename
    # does mis-assign ownership, so the exclusion is doing the work.
    @tag :tmp_dir
    test "read_table.ex is excluded so its usage example does not claim ownership", %{tmp_dir: dir} do
      write(dir, "shared/read_table.ex", schema_in_moduledoc("provider_session_details"))
      write(dir, "provider/session_detail.ex", schema("provider_session_details"))
      write(dir, "provider/reader.ex", query_over("provider_session_details"))

      assert LintAclBoundary.violations(dir) == []

      write(dir, "shared/impostor.ex", schema_in_moduledoc("provider_session_details"))

      assert [{path, message}] = LintAclBoundary.violations(dir)
      assert Path.basename(path) == "reader.ex"
      assert message =~ "shared's `provider_session_details`"
    end

    test "the real tree satisfies the convention" do
      assert LintAclBoundary.violations("lib/klass_hero") == []
    end
  end

  defp write(dir, relative_path, content) do
    path = Path.join(dir, relative_path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
  end

  defp schema(table) do
    """
    defmodule KlassHero.Fixture do
      use Ecto.Schema

      schema "#{table}" do
        field :title, :string
      end
    end
    """
  end

  defp schema_in_moduledoc(table) do
    """
    defmodule KlassHero.Fixture.Marker do
      @moduledoc \"\"\"
          defmodule Example do
            use Ecto.Schema

            schema "#{table}" do
              field :title, :string
            end
          end
      \"\"\"
    end
    """
  end

  defp query_over(table) do
    """
    defmodule KlassHero.Fixture.Reader do
      import Ecto.Query

      def run do
        from(t in "#{table}", select: t.title) |> Repo.all()
      end
    end
    """
  end

  defp query_over(from_table, join_table) do
    """
    defmodule KlassHero.Fixture.Reader do
      import Ecto.Query

      def run do
        from(t in "#{from_table}",
          join: j in "#{join_table}",
          on: j.id == t.child_id,
          select: t.id
        )
        |> Repo.all()
      end
    end
    """
  end

  defp traced_query_over(table) do
    """
    defmodule KlassHero.Fixture.Reader do
      use KlassHero.Shared.Tracing

      import Ecto.Query

      def run do
        acl_span source: "enrollment", target: "program_catalog" do
          from(t in "#{table}", select: t.title) |> Repo.all()
        end
      end
    end
    """
  end
end
