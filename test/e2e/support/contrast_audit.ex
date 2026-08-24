defmodule KlassHeroWeb.E2E.ContrastAudit do
  @moduledoc """
  Measures rendered text contrast in a real browser.

  Complements `mix lint_palette`, which checks the *declared* semantic tokens.
  The two catch genuinely different mistakes and neither substitutes for the
  other: the lint flagged `--fg-link` as badly failing while nothing rendered
  with it, and it sees nothing wrong with `text-hero-grey-500` — a legitimate
  token — which failed on a quarter of the provider dashboard's visible text.

  ## Why this needs a browser

  Contrast is a property of composited pixels, not of class names. A rule has to
  resolve the cascade, the `oklch()` values, and every semi-transparent layer
  between the text and an opaque background. Only a browser does that.

  ## The compositing rules this exists to get right

  A contrast test that invents dramatic failures is worse than no test: it teaches
  everyone to ignore it. Each rule below was added because the version without it
  either fabricated a failure or missed a real one.

  1. **Composite the whole stack, bottom-up.** The first version took the nearest
     non-transparent background and used it directly, reporting `text-white/90` on
     a `bg-white/5` chip inside a **black** sidebar as 1.00:1 — a 5%-alpha white
     over an assumed white base is white. The real ratio is 15.7:1.

  2. **Include positioned overlay siblings, not just ancestors.** A cover band and
     its scrim are siblings of the text (`<div class="absolute inset-0">` beside
     `<div class="relative">`), so an ancestor-only walk never sees them and reports
     hero text as sitting on the page background. That made the one surface a scrim
     exists to bound the one surface this could not measure.

  3. **Apply each element's `opacity`.** It is a separate property from
     `backgroundColor`, so a 20%-opacity blurred decorative blob was composited as a
     solid fill — turning `text-white/70` on black into a fictional 1.47:1. Alpha is
     carried per layer and applied via canvas `globalAlpha`, because canvas is also
     what parses the colour: computed values come back as `oklch()` verbatim here,
     and hand-parsing them fabricates ratios.

  4. **Worst-case real images to black, but not gradients.** An `<img>` or a
     `url()` background is an arbitrary upload, so the question is whether the text
     survives *any* cover. A gradient is palette colours the declared-token lint
     already governs; calling it black fails every dark text on a light gradient.
     A gradient therefore contributes nothing and the layer beneath it is measured —
     the same behaviour this harness shipped with.

  ## Thresholds

  WCAG AA: 4.5:1 for normal text, 3:1 for large text (>=24px, or >=18.66px bold).
  Non-text indicators are `mix lint_palette`'s job, not this one's.
  """

  @audit_js """
  const cv = document.createElement('canvas');
  cv.width = cv.height = 1;
  const ctx = cv.getContext('2d', { willReadFrequently: true });

  // Layers are {color, alpha}. Alpha is the element's `opacity`, which is a separate
  // property from backgroundColor — a 20%-opacity decorative blob composited as a
  // solid fill invents dramatic failures. globalAlpha does the blend because canvas
  // is also what parses the colour: computed values come back as oklch() verbatim,
  // and hand-parsing them is how you fabricate ratios.
  const paint = (layers) => {
    ctx.clearRect(0, 0, 1, 1);
    ctx.globalAlpha = 1;
    ctx.fillStyle = '#FFFFFF';
    ctx.fillRect(0, 0, 1, 1);
    for (const l of layers) {
      if (l.alpha < 0.01) continue;
      ctx.globalAlpha = l.alpha;
      ctx.fillStyle = l.color;
      ctx.fillRect(0, 0, 1, 1);
    }
    ctx.globalAlpha = 1;
    const d = ctx.getImageData(0, 0, 1, 1).data;
    return [d[0], d[1], d[2]];
  };

  const opaqueish = (c) => c && c !== 'rgba(0, 0, 0, 0)' && c !== 'transparent';

  const covers = (layer, el) => {
    const l = layer.getBoundingClientRect();
    const r = el.getBoundingClientRect();
    const x = r.left + r.width / 2;
    const y = r.top + r.height / 2;
    return l.left <= x && l.right >= x && l.top <= y && l.bottom >= y;
  };

  // An <img> or a CSS background-image is an arbitrary upload. Worst-case it to
  // black: the question a scrim exists to answer is whether the text survives ANY
  // cover, not whether this particular photo happens to be light.
  const pushPaint = (node, layers) => {
    const cs = getComputedStyle(node);
    if (cs.visibility === 'hidden' || cs.display === 'none') return;
    const alpha = parseFloat(cs.opacity);
    // Only a real image is worst-cased. url() and <img> are arbitrary uploads, so
    // black is the bound a scrim has to survive. A gradient is palette colours the
    // declared-token lint already governs — calling it black would fail every dark
    // text on a light gradient, which is a fabricated failure, not a found one.
    if (node.tagName === 'IMG' || cs.backgroundImage.includes('url(')) {
      layers.push({ color: '#000000', alpha: alpha });
    }
    if (opaqueish(cs.backgroundColor)) layers.push({ color: cs.backgroundColor, alpha: alpha });
  };

  const paintSubtree = (root, layers) => {
    for (const n of [root, ...root.querySelectorAll('*')]) pushPaint(n, layers);
  };

  const backgroundStack = (el) => {
    const ancestors = [];
    for (let n = el; n && n !== document.documentElement; n = n.parentElement) ancestors.push(n);
    ancestors.reverse();

    const layers = [];
    for (const node of ancestors) {
      pushPaint(node, layers);

      // Overlay siblings. A cover band and its scrim are positioned siblings of the
      // text, not ancestors, so an ancestor-only walk reports the text as sitting on
      // the page background — the exact surface a scrim exists to bound.
      for (const child of node.children) {
        if (child === el || child.contains(el)) continue;
        const ccs = getComputedStyle(child);
        if (ccs.position !== 'absolute' && ccs.position !== 'fixed') continue;
        if (ccs.visibility === 'hidden' || ccs.display === 'none') continue;
        if (!covers(child, el)) continue;
        paintSubtree(child, layers);
      }
    }
    return layers;
  };

  const lum = ([r, g, b]) => {
    const f = (c) => { c /= 255; return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); };
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
  };
  const ratio = (a, b) => {
    const [hi, lo] = [lum(a), lum(b)].sort((x, y) => y - x);
    return (hi + 0.05) / (lo + 0.05);
  };

  const selector = 'a,p,span,h1,h2,h3,h4,h5,li,td,th,label,button,dt,dd,strong,em,small';
  const results = [];

  for (const el of document.querySelectorAll(selector)) {
    if (el.children.length > 0) continue;
    const text = el.textContent.trim();
    if (!text) continue;
    const r = el.getBoundingClientRect();
    if (r.width === 0 || r.height === 0) continue;

    const cs = getComputedStyle(el);
    if (cs.visibility === 'hidden' || cs.opacity === '0') continue;

    const bgLayers = backgroundStack(el);
    const bg = paint(bgLayers);
    const fg = paint(bgLayers.concat([{ color: cs.color, alpha: parseFloat(cs.opacity) }]));

    const size = parseFloat(cs.fontSize);
    const bold = parseInt(cs.fontWeight, 10) >= 700;
    const large = size >= 24 || (size >= 18.66 && bold);
    const floor = large ? 3.0 : 4.5;
    const value = ratio(fg, bg);

    if (value < floor) {
      results.push({
        text: text.slice(0, 40),
        ratio: Math.round(value * 100) / 100,
        floor: floor,
        selector: el.tagName.toLowerCase() + (el.className && typeof el.className === 'string' ? '.' + el.className.trim().split(/\\s+/).slice(0, 3).join('.') : '')
      });
    }
  }

  return results.sort((a, b) => a.ratio - b.ratio);
  """

  @doc """
  Returns every text node on the current page whose contrast is below its WCAG AA
  floor, worst first.

  Each entry is `%{"text" => .., "ratio" => .., "floor" => .., "selector" => ..}`.
  """
  def failures(session) do
    # `execute_script/4` is chainable and returns the session; the callback is the
    # only way out. Sending to self rather than using the return value directly.
    parent = self()

    Wallaby.Browser.execute_script(session, @audit_js, [], fn result ->
      send(parent, {:contrast_audit, result})
    end)

    receive do
      {:contrast_audit, result} -> result
    after
      10_000 -> raise "contrast audit script did not return within 10s"
    end
  end

  @doc """
  Formats failures for an assertion message, so a red build names the offending
  text rather than only a count.
  """
  def format(failures) do
    Enum.map_join(failures, "\n", fn f ->
      "  #{Float.round(f["ratio"] / 1, 2)}:1 (needs #{f["floor"]}) " <>
        "#{f["selector"]} — #{inspect(f["text"])}"
    end)
  end
end
