defmodule Mix.Tasks.LintRawHtml do
  @shortdoc "Check for raw/1 calls in templates (bypasses HEEx auto-escaping)"
  @moduledoc """
  Flags every `raw/1` call in the web layer.

  `raw/1` switches off the automatic HTML escaping that makes HEEx safe by default,
  so each call is an XSS surface that someone has to have reasoned about. This task
  does not claim any of them are bugs — it makes them countable, and forces the
  reasoning to be written down next to the call.

  Sobelow's `XSS.Raw` covers some of this, but `.sobelow-conf` sets `exit: :high`,
  so a medium-confidence finding reports without failing the build. And Credo can't
  see a standalone `.html.heex` file at all, because it parses Elixir AST and a HEEx
  template isn't Elixir. A text-level task is the only thing that sees both.

  Lines containing `raw-html-lint-ignore` — on the same line or the preceding one —
  are excluded, matching `mix lint_typography`'s convention:

      <%!-- raw-html-lint-ignore: sanitized upstream by HtmlSanitizeEx --%>

  ## Usage

      mix lint_raw_html
  """
  use Mix.Task

  @search_dir "lib/klass_hero_web/"
  @suppression_marker "raw-html-lint-ignore"

  # Matches `raw(`, `HTML.raw(` and `Phoenix.HTML.raw(`, but not `raw_body(` or a
  # name that merely ends in raw, like `sanitized_raw(`.
  @raw_call ~r/(?<![\w])raw\(/

  @impl true
  def run(_args) do
    violations =
      @search_dir
      |> Path.join("**/*.{ex,heex}")
      |> Path.wildcard()
      |> Enum.flat_map(&find_violations/1)

    if violations == [] do
      Mix.shell().info("Raw HTML lint passed — no unwaived raw/1 calls found.")
    else
      Mix.shell().error(
        "raw/1 bypasses HEEx escaping. Remove it, or waive the line with " <>
          "`#{@suppression_marker}: <why this input is safe>`:\n"
      )

      Enum.each(violations, fn {file, line_num, line} ->
        Mix.shell().error("  #{file}:#{line_num}: #{String.trim(line)}")
      end)

      Mix.raise("Raw HTML lint failed — #{length(violations)} unwaived raw/1 call(s) found")
    end
  end

  defp find_violations(file) do
    lines =
      file
      |> File.read!()
      |> String.split("\n")

    {_line_num, _prev_line, violations} =
      Enum.reduce(lines, {1, "", []}, fn line, {line_num, prev_line, acc} ->
        has_violation =
          Regex.match?(@raw_call, line) and
            not String.contains?(line, @suppression_marker)

        acc =
          if has_violation and not String.contains?(prev_line, @suppression_marker) do
            [{file, line_num, line} | acc]
          else
            acc
          end

        {line_num + 1, line, acc}
      end)

    Enum.reverse(violations)
  end
end
