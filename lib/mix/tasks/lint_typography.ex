defmodule Mix.Tasks.LintTypography do
  @shortdoc "Check for raw font-display classes in templates (use Theme.typography instead)"
  @moduledoc """
  Checks for raw `font-display` class usage in LiveView and component files.

  All display typography should go through `Theme.typography/1` for consistency.
  Lines containing `typography-lint-ignore` — either on the same line or
  the preceding line — are excluded from checks.

  ## Usage

      mix lint_typography
  """
  use Mix.Task

  @search_dir "lib/klass_hero_web/"
  @excluded_files ["theme.ex"]
  @suppression_marker "typography-lint-ignore"

  @impl true
  def run(_args) do
    violations =
      Path.wildcard(Path.join(@search_dir, "**/*.{ex,heex}"))
      |> Enum.reject(fn path -> Path.basename(path) in @excluded_files end)
      |> Enum.flat_map(&find_violations/1)

    if violations == [] do
      Mix.shell().info("Typography lint passed — no raw font-display usage found.")
    else
      Mix.shell().error("Raw font-display classes found. Use Theme.typography() instead:\n")

      Enum.each(violations, fn {file, line_num, line} ->
        Mix.shell().error("  #{file}:#{line_num}: #{String.trim(line)}")
      end)

      Mix.raise("Typography lint failed — #{length(violations)} violation(s) found")
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
          String.contains?(line, "font-display") and
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
