defmodule Mix.Tasks.LintHeroColorsTest do
  @moduledoc """
  Drives `Mix.Tasks.LintHeroColors`'s pure halves.

  The heroicons case is the load-bearing one: `assets/css/app.css` loads
  `@plugin "../vendor/heroicons"`, which generates tokenless `hero-*` utilities
  under the same prefix as the brand colour scales. The extractor separates them
  structurally — a colour utility always has a prefix before `-hero-`, a bare icon
  class never does — so a regression there floods the lint with false positives
  rather than failing quietly.
  """

  use ExUnit.Case, async: true

  alias Mix.Tasks.LintHeroColors

  describe "parse_theme_tokens/1" do
    test "collects the colour names declared in @theme" do
      css = """
      @theme {
        --color-hero-blue-500: oklch(78% 0.155 210); /* Primary #0fc3ff */
        --color-hero-black: oklch(0% 0 0);
        --font-display: "Plus Jakarta Sans", sans-serif;
      }
      """

      tokens = LintHeroColors.parse_theme_tokens(css)

      assert "hero-blue-500" in tokens
      assert "hero-black" in tokens
      refute "hero-charcoal" in tokens
    end

    test "ignores the :root semantic aliases that reference the scale" do
      css = """
      @theme {
        --color-hero-blue-500: oklch(78% 0.155 210);
      }
      :root {
        --brand-primary: var(--color-hero-blue-500);
      }
      """

      assert LintHeroColors.parse_theme_tokens(css) == MapSet.new(["hero-blue-500"])
    end
  end

  describe "extract_used/1" do
    test "pulls the token name out of a plain utility" do
      assert LintHeroColors.extract_used(~s("bg-hero-yellow")) == ["hero-yellow"]
    end

    test "strips a variant prefix" do
      assert LintHeroColors.extract_used(~s("focus:ring-hero-cyan")) == ["hero-cyan"]
    end

    test "strips an opacity modifier" do
      assert LintHeroColors.extract_used(~s("bg-hero-primary/5")) == ["hero-primary"]
    end

    test "keeps a multi-segment name whole" do
      assert LintHeroColors.extract_used(~s("hover:bg-hero-yellow-dark")) == ["hero-yellow-dark"]
    end

    test "handles an arbitrary-variant prefix" do
      assert LintHeroColors.extract_used(~s("has-[:checked]:bg-hero-yellow")) == ["hero-yellow"]
    end

    test "ignores a bare heroicon class" do
      assert LintHeroColors.extract_used(~s(<.icon name="hero-plus-mini" class="w-5" />)) == []
    end

    test "ignores a heroicon sitting in a class list beside a colour utility" do
      assert LintHeroColors.extract_used(~s("hero-check-mini bg-hero-yellow-500")) ==
               ["hero-yellow-500"]
    end

    test "returns every token on the line, in order, without duplicates" do
      line = ~s("bg-hero-yellow hover:bg-hero-yellow-dark text-hero-charcoal bg-hero-yellow")

      assert LintHeroColors.extract_used(line) ==
               ["hero-yellow", "hero-yellow-dark", "hero-charcoal"]
    end
  end

  describe "violations/2" do
    @tag :tmp_dir
    test "passes a tree whose every hero-* utility resolves to a token", %{tmp_dir: dir} do
      theme = write_theme(dir, ~w(hero-yellow-500 hero-black-100))
      write(dir, "components/ui.ex", ~s(class="bg-hero-yellow-500 text-hero-black-100"))

      assert LintHeroColors.violations(Path.join(dir, "web"), theme) == []
    end

    @tag :tmp_dir
    test "flags a utility with no matching token", %{tmp_dir: dir} do
      theme = write_theme(dir, ~w(hero-yellow-500))
      write(dir, "components/ui.ex", ~s(class="bg-hero-charcoal"))

      assert [{path, line_num, token}] = LintHeroColors.violations(Path.join(dir, "web"), theme)
      assert Path.basename(path) == "ui.ex"
      assert line_num == 1
      assert token == "hero-charcoal"
    end

    @tag :tmp_dir
    test "scans .heex templates as well as .ex modules", %{tmp_dir: dir} do
      theme = write_theme(dir, ~w(hero-blue-500))
      write(dir, "live/page.html.heex", ~s(<div class="text-hero-cyan">hi</div>))

      assert [{path, _, "hero-cyan"}] = LintHeroColors.violations(Path.join(dir, "web"), theme)
      assert Path.basename(path) == "page.html.heex"
    end

    @tag :tmp_dir
    test "reports the line the violation is on, not the first line", %{tmp_dir: dir} do
      theme = write_theme(dir, ~w(hero-blue-500))
      write(dir, "components/ui.ex", "line one\nline two\nclass=\"bg-hero-primary\"\n")

      assert [{_, 3, "hero-primary"}] = LintHeroColors.violations(Path.join(dir, "web"), theme)
    end

    @tag :tmp_dir
    test "stays silent on a tree of nothing but heroicons", %{tmp_dir: dir} do
      theme = write_theme(dir, ~w(hero-blue-500))
      write(dir, "components/ui.ex", ~s(<.icon name="hero-academic-cap-mini" />))

      assert LintHeroColors.violations(Path.join(dir, "web"), theme) == []
    end

    @tag :tmp_dir
    test "the ignore marker exempts its own line", %{tmp_dir: dir} do
      theme = write_theme(dir, ~w(hero-blue-500))
      write(dir, "live/page.ex", ~s(id="program-hero-image" <%!-- hero-color-lint-ignore --%>))

      assert LintHeroColors.violations(Path.join(dir, "web"), theme) == []
    end

    @tag :tmp_dir
    test "the ignore marker exempts the following line", %{tmp_dir: dir} do
      theme = write_theme(dir, ~w(hero-blue-500))

      write(dir, "live/page.ex", """
      <%!-- hero-color-lint-ignore: a DOM id, not a class --%>
      id="program-hero-image"
      """)

      assert LintHeroColors.violations(Path.join(dir, "web"), theme) == []
    end
  end

  defp write_theme(dir, tokens) do
    path = Path.join(dir, "app.css")
    body = Enum.map_join(tokens, "\n", &"  --color-#{&1}: oklch(50% 0 0);")
    File.write!(path, "@theme {\n#{body}\n}\n")
    path
  end

  defp write(dir, relative, contents) do
    path = Path.join([dir, "web", relative])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
  end
end
