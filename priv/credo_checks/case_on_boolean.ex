defmodule KlassHero.CredoChecks.CaseOnBoolean do
  @moduledoc """
  Flags `case` expressions whose clauses are only `true` / `false` / `_`.

  Lives in `priv/` rather than `lib/` because it is dev-only tooling and must not
  compile into the release. `.credo.exs` loads it through `requires:`.
  """
  use Credo.Check,
    base_priority: :normal,
    category: :refactor,
    param_defaults: [],
    explanations: [
      check: """
      A `case` that only matches `true` and `false` is an `if` wearing a costume.

      It is a reliable marker of generated code: the model reaches for the most
      general control-flow construct instead of the one that fits, and the next
      generation copies it. Both forms compile and behave identically, so nothing
      else in the toolchain objects.

          # Bad
          case user.active? do
            true -> :ok
            false -> :error
          end

          # Good
          if user.active?, do: :ok, else: :error

      Note the two are not always interchangeable: `case` raises `CaseClauseError`
      on a non-boolean, where `if` treats every value except `nil`/`false` as truthy.
      Where that distinction is load-bearing, say so and waive the line.
      """
    ]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Credo.SourceFile.ast()
    |> find_boolean_cases(issue_meta)
  end

  defp find_boolean_cases(ast, issue_meta) do
    {_ast, issues} = Macro.prewalk(ast, [], &traverse(&1, &2, issue_meta))
    issues
  end

  defp traverse({:case, meta, [_subject, [do: clauses]]} = node, issues, issue_meta) when is_list(clauses) do
    if boolean_only?(clauses) do
      {node, [issue_for(issue_meta, meta[:line]) | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _issue_meta), do: {node, issues}

  # Every clause head is `true`, `false`, or a catch-all, and at least one is an
  # actual boolean literal — so a `case` used purely as a two-way branch. A guard or
  # any other pattern means the `case` is earning its keep.
  defp boolean_only?(clauses) do
    heads = Enum.map(clauses, &clause_head/1)

    Enum.all?(heads, &(&1 in [:boolean, :catch_all])) and :boolean in heads
  end

  defp clause_head({:->, _meta, [[true], _body]}), do: :boolean
  defp clause_head({:->, _meta, [[false], _body]}), do: :boolean
  defp clause_head({:->, _meta, [[{:_, _, _}], _body]}), do: :catch_all
  defp clause_head(_clause), do: :other

  defp issue_for(issue_meta, line_no) do
    format_issue(issue_meta,
      message: "`case` on a boolean — use `if`/`else`, or a guard, instead.",
      trigger: "case",
      line_no: line_no
    )
  end
end
