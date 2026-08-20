defmodule Mix.Tasks.LintHeroColors do
  @shortdoc "Check that every hero-* colour utility resolves to an @theme token"
  @moduledoc """
  Checks `hero-*` colour utilities in LiveView and component files against the
  `--color-*` tokens declared in `assets/css/app.css`'s `@theme` block.

  Tailwind v4 is CSS-first: it emits a utility only when a matching custom
  property exists, and emits *nothing* — silently, with no build warning — when
  one does not. A class like `bg-hero-yellow` (v3's unnumbered base colour) or
  `hover:bg-hero-yellow-dark` (a v3 `-dark` suffix) therefore renders as
  inherited or transparent rather than failing loudly. This task is the missing
  diagnostic.

  ## The heroicons collision

  `app.css` loads `@plugin "../vendor/heroicons"`, which generates icon
  utilities under the *same* `hero-*` prefix — `hero-plus-mini` and friends,
  legitimately tokenless. They are separated structurally rather than by an
  allowlist: a colour utility always carries a prefix (`bg-`, `ring-`,
  `hover:border-`) so the name is preceded by `-`, while a bare icon class is
  preceded by a quote or a space.

  That is why no list of utility prefixes appears here. Such a list is a closed
  enum that goes stale, and a prefix nobody enumerated would be a class nobody
  checks — reproducing the exact silent miss this task exists to catch.

  ## Usage

      mix lint_hero_colors

  Lines containing `hero-color-lint-ignore` — on the same line or the preceding
  one — are skipped, for the rare `-hero-` substring that is not a class at all
  (a DOM id, say).
  """
  use Mix.Task

  @search_dir "lib/klass_hero_web/"
  @theme_file "assets/css/app.css"
  @suppression_marker "hero-color-lint-ignore"

  # A `--color-*` declaration, not a `var(--color-*)` reference: the trailing
  # colon is what separates the two.
  @token_pattern ~r/--color-([a-z0-9-]+)\s*:/

  # One leading character before `-hero-` is the whole heroicon discriminator.
  @usage_pattern ~r/[a-z0-9]-hero-([a-z0-9]+(?:-[a-z0-9]+)*)/

  @impl true
  def run(_args) do
    case violations(@search_dir, @theme_file) do
      [] ->
        Mix.shell().info("Hero colour lint passed — every hero-* utility resolves to a token.")

      violations ->
        Mix.shell().error("hero-* classes with no matching --color-* token in @theme:\n")

        Enum.each(violations, fn {file, line_num, token} ->
          Mix.shell().error("  #{file}:#{line_num}: #{token}")
        end)

        Mix.raise("Hero colour lint failed — #{length(violations)} violation(s) found")
    end
  end

  @doc """
  Returns `{file, line_number, token}` for every `hero-*` utility under `dir`
  with no matching `--color-*` declaration in the stylesheet at `theme_path`.
  """
  def violations(dir, theme_path) do
    defined = theme_path |> File.read!() |> parse_theme_tokens()

    dir
    |> Path.join("**/*.{ex,heex}")
    |> Path.wildcard()
    |> Enum.flat_map(&file_violations(&1, defined))
  end

  @doc """
  Extracts the colour names declared in a stylesheet's `@theme` block.
  """
  def parse_theme_tokens(css) do
    @token_pattern
    |> Regex.scan(css, capture: :all_but_first)
    |> MapSet.new(fn [name] -> name end)
  end

  @doc """
  Extracts the `hero-*` token names a line of source references, in order and
  without duplicates. Variant prefixes and `/opacity` modifiers fall away; bare
  heroicon classes never match.
  """
  def extract_used(line) do
    @usage_pattern
    |> Regex.scan(line, capture: :all_but_first)
    |> Enum.map(fn [name] -> "hero-" <> name end)
    |> Enum.uniq()
  end

  defp file_violations(file, defined) do
    {_line_num, _prev_line, violations} =
      file
      |> File.read!()
      |> String.split("\n")
      |> Enum.reduce({1, "", []}, fn line, {line_num, prev_line, acc} ->
        acc =
          if suppressed?(line, prev_line) do
            acc
          else
            line
            |> extract_used()
            |> Enum.reject(&(&1 in defined))
            |> Enum.reduce(acc, &[{file, line_num, &1} | &2])
          end

        {line_num + 1, line, acc}
      end)

    Enum.reverse(violations)
  end

  defp suppressed?(line, prev_line) do
    String.contains?(line, @suppression_marker) or
      String.contains?(prev_line, @suppression_marker)
  end
end
