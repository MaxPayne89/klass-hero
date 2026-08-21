defmodule Mix.Tasks.LintPaletteTest do
  @moduledoc """
  Drives `Mix.Tasks.LintPalette`'s pure halves, plus one check against the real
  `assets/css/app.css`.

  Two cases are load-bearing:

  * **Hero Black's header.** Its tokens carry `/* Pure black */` with no hex, so
    a naive "next inline hex below the header" rule attributes the header to the
    *following* scale and reports a violation that does not exist. The header
    check is bounded by the next header for exactly this reason.

  * **The vacuity guard.** Every check here is "find the disagreements", which a
    broken regex satisfies by finding nothing. Asserting the real stylesheet
    parses into a substantial number of declarations is what stops the lint from
    passing because it stopped looking.
  """

  use ExUnit.Case, async: true

  alias Mix.Tasks.LintPalette

  @theme_file "assets/css/app.css"

  describe "oklch_to_rgb/1 and to_hex/1" do
    test "converts OKLCH to the sRGB hex a browser renders" do
      cases = [
        {{0.0, 0.0, 0.0}, "#000000"},
        {{1.0, 0.0, 0.0}, "#FFFFFF"},
        {{0.82, 0.0, 0.0}, "#C4C4C4"},
        {{0.78, 0.155, 210.0}, "#00D1EE"},
        {{0.97, 0.22, 105.0}, "#FFFB00"}
      ]

      for {oklch, expected} <- cases do
        actual = oklch |> LintPalette.oklch_to_rgb() |> LintPalette.to_hex()

        assert actual == expected,
               "oklch#{inspect(oklch)} should render #{expected}, got #{actual}"
      end
    end

    test "clips out-of-gamut channels into range rather than overflowing" do
      # Chroma 0.4 is far outside sRGB at any lightness. The specific clipped
      # triple is not the contract — staying inside 0..255 is, because an
      # out-of-range channel would corrupt every ratio computed from it.
      for lightness <- [0.1, 0.5, 0.97], hue <- [0.0, 105.0, 210.0, 330.0] do
        {r, g, b} = LintPalette.oklch_to_rgb({lightness, 0.4, hue})

        for channel <- [r, g, b] do
          assert channel in 0..255,
                 "oklch(#{lightness * 100}% 0.4 #{hue}) produced out-of-range #{channel}"
        end
      end
    end
  end

  describe "contrast_ratio/2" do
    test "matches the WCAG 2.x endpoints" do
      cases = [
        {{0, 0, 0}, {255, 255, 255}, 21.0},
        {{255, 255, 255}, {255, 255, 255}, 1.0},
        {{0, 0, 0}, {0, 0, 0}, 1.0}
      ]

      for {a, b, expected} <- cases do
        actual = LintPalette.contrast_ratio(a, b)

        assert_in_delta actual, expected, 0.01, "#{inspect(a)} on #{inspect(b)} should be #{expected}:1, got #{actual}"
      end
    end

    test "is symmetric in its arguments" do
      a = LintPalette.contrast_ratio({0, 209, 238}, {0, 0, 0})
      b = LintPalette.contrast_ratio({0, 0, 0}, {0, 209, 238})

      assert_in_delta a, b, 0.0001
    end
  end

  describe "parse_declarations/1" do
    test "captures the value, the claimed hex, and the line" do
      css = """
      @theme {
        --color-hero-blue-500: oklch(78% 0.155 210); /* Primary #00D1EE */
        --color-hero-black: oklch(0% 0 0); /* Pure black */
        --font-display: "Plus Jakarta Sans", sans-serif;
      }
      """

      decls = LintPalette.parse_declarations(css)

      assert %{oklch: {0.78, 0.155, 210.0}, hex: "00D1EE", line: 2} = decls["hero-blue-500"]
      assert %{oklch: {+0.0, +0.0, +0.0}, hex: nil, line: 3} = decls["hero-black"]
      refute Map.has_key?(decls, "font-display")
    end

    test "ignores var() references, which are not declarations" do
      css = """
      :root {
        --brand-primary: var(--color-hero-blue-500);
      }
      """

      assert LintPalette.parse_declarations(css) == %{}
    end
  end

  describe "mirror_violations/1" do
    test "reports a daisy slot that has drifted from the token it mirrors" do
      decls =
        LintPalette.parse_declarations("""
          --color-primary: oklch(78% 0.16 195);
          --color-hero-blue-500: oklch(78% 0.155 210);
        """)

      assert [violation] = LintPalette.mirror_violations(decls)
      assert violation =~ "--color-primary"
      assert violation =~ "--color-hero-blue-500"
    end

    test "passes when the pair agrees" do
      decls =
        LintPalette.parse_declarations("""
          --color-primary: oklch(78% 0.155 210);
          --color-hero-blue-500: oklch(78% 0.155 210);
        """)

      assert LintPalette.mirror_violations(decls) == []
    end
  end

  describe "contrast_violations/1" do
    test "reports a pair below the AA floor and passes one above it" do
      cases = [
        {"oklch(98% 0.02 210)", :violation},
        {"oklch(20% 0.05 210)", :ok}
      ]

      for {content, expected} <- cases do
        decls =
          LintPalette.parse_declarations("""
            --color-primary: oklch(78% 0.155 210);
            --color-primary-content: #{content};
          """)

        actual = if LintPalette.contrast_violations(decls) == [], do: :ok, else: :violation

        assert actual == expected,
               "primary-content #{content} should be #{expected}"
      end
    end

    test "fans a bare -content slot out across every numbered background" do
      decls =
        LintPalette.parse_declarations("""
          --color-base-100: oklch(93% 0.06 75);
          --color-base-200: oklch(90% 0.08 75);
          --color-base-content: oklch(93% 0.06 75);
        """)

      violations = LintPalette.contrast_violations(decls)

      assert length(violations) == 2
      assert Enum.any?(violations, &(&1 =~ "--color-base-100"))
      assert Enum.any?(violations, &(&1 =~ "--color-base-200"))
    end
  end

  describe "comment_violations/1" do
    test "reports a comment claiming a hex the value does not render" do
      decls = LintPalette.parse_declarations("  --color-x: oklch(78% 0.155 210); /* #0FC3FF */")

      assert [violation] = LintPalette.comment_violations(decls)
      assert violation =~ "renders #00D1EE"
      assert violation =~ "claims #0FC3FF"
    end

    test "passes a truthful comment, and a comment carrying no hex at all" do
      decls =
        LintPalette.parse_declarations("""
          --color-x: oklch(78% 0.155 210); /* #00D1EE */
          --color-y: oklch(0% 0 0); /* Pure black */
        """)

      assert LintPalette.comment_violations(decls) == []
    end

    test "compares case-insensitively" do
      decls = LintPalette.parse_declarations("  --color-x: oklch(78% 0.155 210); /* #00d1ee */")

      assert LintPalette.comment_violations(decls) == []
    end
  end

  describe "header_violations/2" do
    test "reports a scale header disagreeing with its own scale's token" do
      css = """
      /* Hero Blue #0fc3ff */
      --color-hero-blue-500: oklch(78% 0.155 210); /* Primary #00D1EE */
      """

      assert [violation] = LintPalette.header_violations(css, LintPalette.parse_declarations(css))
      assert violation =~ "claims #0FC3FF"
      assert violation =~ "claims #00D1EE"
    end

    test "skips a scale whose tokens carry no inline hex" do
      css = """
      /* Hero Black #000000 */
      --color-hero-black: oklch(0% 0 0); /* Pure black */

      /* Hero Cream #FAF0E3 */
      --color-hero-cream-100: oklch(96% 0.02 75); /* Primary #FAF0E3 */
      """

      assert LintPalette.header_violations(css, LintPalette.parse_declarations(css)) == []
    end
  end

  describe "the real stylesheet" do
    test "has no palette inconsistencies" do
      assert LintPalette.violations(@theme_file) == []
    end

    test "parses into a substantial palette, so a broken regex cannot pass vacuously" do
      decls = @theme_file |> File.read!() |> LintPalette.parse_declarations()

      assert map_size(decls) > 50,
             "expected the full palette, parsed only #{map_size(decls)} declarations"

      assert Enum.count(decls, fn {_, %{hex: hex}} -> hex end) > 5,
             "expected several hex-annotated declarations for the comment check to bite"

      assert Enum.count(decls, fn {name, _} -> String.ends_with?(name, "-content") end) > 5,
             "expected several -content slots for the contrast check to bite"
    end
  end
end
