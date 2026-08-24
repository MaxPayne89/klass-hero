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

  ## The compositing rule this exists to get right

  The first version of this walked up to the nearest non-transparent background
  and used it directly. That reported `text-white/90` on a `bg-white/5` chip
  inside a **black** sidebar as 1.00:1 — white on white — because a 5%-alpha
  white composited over an assumed white base is white. The real ratio is 15.7:1.

  So the whole ancestor stack is composited bottom-up onto an opaque base. A
  contrast test that invents dramatic failures is worse than no test: it teaches
  everyone to ignore it.

  ## Thresholds

  WCAG AA: 4.5:1 for normal text, 3:1 for large text (>=24px, or >=18.66px bold).
  Non-text indicators are `mix lint_palette`'s job, not this one's.
  """

  @audit_js """
  const cv = document.createElement('canvas');
  cv.width = cv.height = 1;
  const ctx = cv.getContext('2d', { willReadFrequently: true });

  const paint = (layers) => {
    ctx.clearRect(0, 0, 1, 1);
    ctx.fillStyle = '#FFFFFF';
    ctx.fillRect(0, 0, 1, 1);
    for (const c of layers) { ctx.fillStyle = c; ctx.fillRect(0, 0, 1, 1); }
    const d = ctx.getImageData(0, 0, 1, 1).data;
    return [d[0], d[1], d[2]];
  };

  const backgroundStack = (el) => {
    const layers = [];
    let n = el;
    while (n && n !== document.documentElement) {
      const c = getComputedStyle(n).backgroundColor;
      if (c && c !== 'rgba(0, 0, 0, 0)' && c !== 'transparent') layers.push(c);
      n = n.parentElement;
    }
    const root = getComputedStyle(document.body).backgroundColor;
    if (root && root !== 'rgba(0, 0, 0, 0)') layers.push(root);
    return layers.reverse();
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
    const fg = paint(bgLayers.concat([cs.color]));

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
