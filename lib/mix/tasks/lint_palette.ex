defmodule Mix.Tasks.LintPalette do
  @shortdoc "Check that the app.css palette is internally consistent"
  @moduledoc """
  Checks three properties of the colour palette in `assets/css/app.css`.

  The file declares colours twice: once in the daisyUI theme plugin block, and
  once in the Tailwind v4 `@theme` block. Nothing forces the two to agree, so
  they drifted — `--color-primary` and `--color-hero-blue-500` were 15° apart in
  hue while both claiming to be "Hero Blue" (#1408). A daisy-driven element and
  a `@theme`-driven element rendered different blues, and only a side-by-side
  comparison could reveal it.

  ## The three checks

  1. **Mirrored slots agree.** Every daisyUI slot that mirrors a `@theme` token
     must hold an identical `oklch()` value.

  2. **Every foreground/background pair clears WCAG AA.** daisyUI pairs
     `--color-X` with `--color-X-content`; the pair must reach 4.5:1. Five pairs
     did not — `--color-success` sat at 2.33:1 — because the daisy slots live
     outside the vocabulary `DESIGN.md` governs and were never audited.

  3. **Hex comments tell the truth.** Every `/* … #RRGGBB */` must equal the hex
     its `oklch()` actually renders. Every one of them was wrong: the value
     beside `#0fc3ff` renders `#00D1EE`. A rotten comment is not cosmetic — it
     is how `priv/brand/generate_icons.mjs` acquired a hand-copied hex that no
     longer matches the token it says it mirrors.

  Contrast pairs are *derived*, not enumerated: a hardcoded list is a closed
  enum that goes stale, and a slot nobody listed is a slot nobody checks.

  ## Usage

      mix lint_palette
  """
  use Mix.Task

  @theme_file "assets/css/app.css"
  @min_contrast 4.5

  # daisyUI slot => the @theme token it mirrors. This one *is* an explicit map,
  # because the relationship is semantic rather than structural: nothing in the
  # names says `base-100` means `hero-pink-50`.
  @mirrors %{
    "base-100" => "hero-pink-50",
    "base-content" => "hero-black",
    "primary" => "hero-blue-500",
    "secondary" => "hero-grey-400",
    "accent" => "hero-yellow-500"
  }

  @declaration ~r/^\s*--color-([a-z0-9-]+):\s*oklch\(\s*([\d.]+)%\s+([\d.]+)\s+([\d.]+)\s*\)\s*;(.*)$/
  @standalone_comment ~r/^\s*\/\*[^*]*#([0-9a-fA-F]{6})[^*]*\*\/\s*$/
  @comment_hex ~r/#([0-9a-fA-F]{6})/

  @impl true
  def run(_args) do
    case violations(@theme_file) do
      [] ->
        Mix.shell().info("Palette lint passed — slots agree, pairs clear AA, comments are true.")

      violations ->
        Mix.shell().error("Palette inconsistencies in #{@theme_file}:\n")
        Enum.each(violations, &Mix.shell().error("  " <> &1))
        Mix.raise("Palette lint failed — #{length(violations)} violation(s) found")
    end
  end

  @doc """
  Returns a human-readable violation string for every palette inconsistency in
  the stylesheet at `path`.
  """
  def violations(path) do
    css = File.read!(path)
    decls = parse_declarations(css)

    mirror_violations(decls) ++
      contrast_violations(decls) ++
      comment_violations(decls) ++
      header_violations(css, decls)
  end

  @doc """
  Parses every `--color-*: oklch(…)` declaration into
  `%{name => %{oklch: {l, c, h}, hex: binary | nil, line: pos_integer}}`.

  `l` is a 0..1 fraction; `hex` is the value claimed by a trailing comment, if
  the declaration carries one.
  """
  def parse_declarations(css) do
    css
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce(%{}, fn {line, num}, acc ->
      case Regex.run(@declaration, line, capture: :all_but_first) do
        [name, l, c, h, rest] ->
          Map.put(acc, name, %{
            oklch: {to_f(l) / 100, to_f(c), to_f(h)},
            hex: claimed_hex(rest),
            line: num
          })

        nil ->
          acc
      end
    end)
  end

  @doc """
  Violations where a daisyUI slot has drifted from the `@theme` token it mirrors.
  """
  def mirror_violations(decls) do
    Enum.flat_map(Enum.sort(@mirrors), fn {slot, token} ->
      case {Map.get(decls, slot), Map.get(decls, token)} do
        {%{oklch: same}, %{oklch: same}} ->
          []

        {%{oklch: slot_value, line: line}, %{oklch: token_value}} ->
          [
            "#{@theme_file}:#{line}: --color-#{slot} #{fmt(slot_value)} has drifted from " <>
              "--color-#{token} #{fmt(token_value)} — both are the same colour"
          ]

        _ ->
          []
      end
    end)
  end

  @doc """
  Violations where a `--color-X` / `--color-X-content` pair falls below AA.

  A `-content` slot pairs with its exact prefix when one exists, and otherwise
  with every numbered variant of that prefix — which is how `base-content`
  reaches `base-100`, `base-200`, and `base-300`.
  """
  def contrast_violations(decls) do
    for {name, %{oklch: fg, line: line}} <- Enum.sort(decls),
        prefix = String.replace_suffix(name, "-content", ""),
        prefix != name,
        bg_name <- backgrounds_for(prefix, decls),
        ratio = contrast_ratio(oklch_to_rgb(fg), oklch_to_rgb(decls[bg_name].oklch)),
        ratio < @min_contrast do
      "#{@theme_file}:#{line}: --color-#{name} on --color-#{bg_name} is " <>
        "#{fmt_ratio(ratio)}:1, below the #{@min_contrast}:1 WCAG AA floor"
    end
  end

  @doc """
  Violations where a declaration's trailing comment claims a hex its `oklch()`
  does not render.
  """
  def comment_violations(decls) do
    for {name, %{oklch: value, hex: claimed, line: line}} <- Enum.sort(decls),
        claimed,
        actual = value |> oklch_to_rgb() |> to_hex(),
        "#" <> String.upcase(claimed) != actual do
      "#{@theme_file}:#{line}: --color-#{name} renders #{actual} but its comment " <>
        "claims ##{String.upcase(claimed)}"
    end
  end

  @doc """
  Violations where a standalone scale-header comment claims a hex that disagrees
  with its own scale's inline hex.

  A header owns the lines up to the next header, so a scale whose tokens carry
  no inline hex — Hero Black's `/* Pure black */` — is skipped rather than
  matched against the *following* scale's value.

  Written with `flat_map` rather than a comprehension on purpose: in a `for`,
  `x = expr` is a filter as well as a binding, so a nil from `Enum.find/2`
  silently drops the element. That cost the **last** header in the file its
  check, since it alone has no header after it.
  """
  def header_violations(css, decls) do
    inline = decls |> Map.values() |> Enum.filter(& &1.hex) |> Enum.sort_by(& &1.line)
    headers = header_lines(css)
    header_nums = Enum.map(headers, &elem(&1, 0))

    Enum.flat_map(headers, fn {num, claimed} ->
      limit = Enum.find(header_nums, :infinity, &(&1 > num))
      own = Enum.find(inline, &(&1.line > num and &1.line < limit))

      if own && String.upcase(claimed) != String.upcase(own.hex) do
        [
          "#{@theme_file}:#{num}: scale header claims ##{String.upcase(claimed)} but the " <>
            "scale's own token on line #{own.line} claims ##{String.upcase(own.hex)}"
        ]
      else
        []
      end
    end)
  end

  defp header_lines(css) do
    css
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, num} ->
      case Regex.run(@standalone_comment, line, capture: :all_but_first) do
        [claimed] -> [{num, claimed}]
        nil -> []
      end
    end)
  end

  @doc """
  Converts an OKLCH triple to an sRGB `{r, g, b}` tuple of 0..255 integers,
  gamut-clipped per channel.
  """
  def oklch_to_rgb({l, c, h}) do
    rad = h * :math.pi() / 180
    a = c * :math.cos(rad)
    b = c * :math.sin(rad)

    [lc, mc, sc] =
      Enum.map(
        [
          l + 0.3963377774 * a + 0.2158037573 * b,
          l - 0.1055613458 * a - 0.0638541728 * b,
          l - 0.0894841775 * a - 1.2914855480 * b
        ],
        &(&1 * &1 * &1)
      )

    {
      encode(4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc),
      encode(-1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc),
      encode(-0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc)
    }
  end

  @doc """
  The WCAG 2.x contrast ratio between two sRGB colours, from 1.0 to 21.0.
  """
  def contrast_ratio(rgb_a, rgb_b) do
    a = relative_luminance(rgb_a)
    b = relative_luminance(rgb_b)
    {hi, lo} = if a >= b, do: {a, b}, else: {b, a}
    (hi + 0.05) / (lo + 0.05)
  end

  @doc """
  Formats an sRGB tuple as an uppercase `#RRGGBB` string.
  """
  def to_hex({r, g, b}) do
    "#" <>
      ([r, g, b]
       |> Enum.map_join(&(&1 |> Integer.to_string(16) |> String.pad_leading(2, "0")))
       |> String.upcase())
  end

  defp backgrounds_for(prefix, decls) do
    if Map.has_key?(decls, prefix) do
      [prefix]
    else
      decls
      |> Map.keys()
      |> Enum.filter(&Regex.match?(~r/^#{Regex.escape(prefix)}-\d+$/, &1))
      |> Enum.sort()
    end
  end

  defp relative_luminance({r, g, b}) do
    [lr, lg, lb] = Enum.map([r, g, b], &linearize(&1 / 255))
    0.2126 * lr + 0.7152 * lg + 0.0722 * lb
  end

  defp linearize(c) when c <= 0.04045, do: c / 12.92
  defp linearize(c), do: :math.pow((c + 0.055) / 1.055, 2.4)

  defp encode(x) do
    clipped = x |> max(0.0) |> min(1.0)

    value =
      if clipped <= 0.0031308,
        do: 12.92 * clipped,
        else: 1.055 * :math.pow(clipped, 1 / 2.4) - 0.055

    round(value * 255)
  end

  defp claimed_hex(rest) do
    case Regex.run(@comment_hex, rest, capture: :all_but_first) do
      [hex] -> hex
      nil -> nil
    end
  end

  defp to_f(string) do
    {value, _} = Float.parse(string)
    value
  end

  defp fmt({l, c, h}), do: "oklch(#{trim(l * 100)}% #{trim(c)} #{trim(h)})"

  defp fmt_ratio(ratio), do: :erlang.float_to_binary(ratio, decimals: 2)

  defp trim(float) do
    rounded = Float.round(float, 4)
    if rounded == Float.round(rounded, 0), do: trunc(rounded), else: rounded
  end
end
