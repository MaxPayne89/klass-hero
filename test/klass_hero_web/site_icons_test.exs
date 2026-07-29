defmodule KlassHeroWeb.SiteIconsTest do
  @moduledoc """
  Covers the site-icon surface: the `<link>` declarations, that the assets are
  served, and that `favicon.ico` is structurally sound.

  The markup and reachability tests would have passed the whole time the favicon
  was broken (#1159) — only the structure tests cover the actual root cause: a
  paletted 8bpp entry whose 1-bit AND mask clipped every antialiased stroke, at
  the 32x32 size Chrome requests on a 2x display.

  These assert the committed bytes are well-formed, never that they are current —
  a stale ICO is still a valid ICO. Regeneration from `priv/brand/kh-mark.svg` is
  gated by the `site-icons` job in `.github/workflows/ci.yml` (#1163).
  """
  use KlassHeroWeb.ConnCase, async: true

  @favicon Path.join([:code.priv_dir(:klass_hero), "static", "favicon.ico"])
  @apple_touch Path.join([
                 :code.priv_dir(:klass_hero),
                 "static",
                 "images",
                 "apple-touch-icon.png"
               ])
  @png_signature <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>
  @expected_entries [{16, 16}, {32, 32}, {48, 48}]

  describe "root layout icon declarations" do
    setup %{conn: conn} do
      # `get/2` on a LiveView route renders the DEAD view, which IS wrapped in
      # root.html.heex. `live/2` returns the connected re-render with the root
      # layout stripped, so the same assertion there could never fail.
      html = conn |> get(~p"/") |> html_response(200)

      %{doc: LazyHTML.from_document(html)}
    end

    test "declares the ICO — Safari and non-browser clients never use the SVG", %{doc: doc} do
      assert "/favicon.ico" in icon_hrefs(doc, ~s(link[rel="icon"]))
    end

    test "declares the SVG icon for Chromium and Firefox", %{doc: doc} do
      assert "/images/icon.svg" in icon_hrefs(doc, ~s(link[rel="icon"][type="image/svg+xml"]))
    end

    test "declares an apple-touch-icon so iOS uses the mark, not a screenshot", %{doc: doc} do
      assert "/images/apple-touch-icon.png" in icon_hrefs(doc, ~s(link[rel="apple-touch-icon"]))
    end

    test "the declared ICO size is one the file actually ships", %{doc: doc} do
      declared = declared_size(doc, ~s(link[href^="/favicon.ico"]))
      shipped = Enum.map(ico_entries(File.read!(@favicon)), &{&1.width, &1.height})

      assert declared in shipped,
             "layout declares #{inspect(declared)} but favicon.ico ships #{inspect(shipped)} — " <>
               "ICO_SIZES in generate_icons.mjs changed without updating root.html.heex"
    end

    test "the declared apple-touch size matches the PNG", %{doc: doc} do
      declared = declared_size(doc, ~s(link[rel="apple-touch-icon"]))

      assert declared == png_dimensions(File.read!(@apple_touch)),
             "layout declares #{inspect(declared)} — check APPLE_TOUCH_SIZE in generate_icons.mjs"
    end
  end

  describe "icon assets are served" do
    for {path, description} <- [
          {"/favicon.ico", "legacy ICO"},
          {"/images/icon.svg", "vector icon"},
          {"/images/apple-touch-icon.png", "apple touch icon"}
        ] do
      test "serves the #{description} at #{path}", %{conn: conn} do
        conn = get(conn, unquote(path))

        assert conn.status == 200,
               "#{unquote(path)} returned #{conn.status}. Plug.Static's :only matches the " <>
                 "FIRST path segment — check KlassHeroWeb.static_paths/0 covers it."

        refute conn.resp_body == ""
      end
    end
  end

  describe "favicon.ico structure" do
    setup do
      %{entries: ico_entries(File.read!(@favicon))}
    end

    test "ships one entry per required size", %{entries: entries} do
      assert Enum.map(entries, &{&1.width, &1.height}) == @expected_entries
    end

    test "every entry is 32bpp truecolour — never paletted", %{entries: entries} do
      for entry <- entries do
        assert entry.bpp == 32,
               "#{entry.width}x#{entry.height} entry is #{entry.bpp}bpp. A paletted entry " <>
                 "carries a 1-bit AND mask that clips antialiasing — the #1159 defect."

        assert entry.palette == 0
        assert entry.planes == 1
      end
    end

    test "every payload is a PNG, so no BMP AND-mask path is reachable", %{entries: entries} do
      for entry <- entries do
        assert binary_part(entry.payload, 0, 8) == @png_signature,
               "#{entry.width}x#{entry.height} payload is not PNG-encoded"
      end
    end

    test "each PNG's own IHDR agrees with its directory entry", %{entries: entries} do
      for entry <- entries do
        assert png_dimensions(entry.payload) == {entry.width, entry.height},
               "directory claims #{entry.width}x#{entry.height} but the PNG disagrees"
      end
    end
  end

  # `~p` appends a cache-busting query (`?vsn=d`) to known static paths.
  defp icon_hrefs(doc, selector) do
    doc
    |> LazyHTML.query(selector)
    |> LazyHTML.attribute("href")
    |> Enum.map(&(&1 |> String.split("?") |> hd()))
  end

  defp declared_size(doc, selector) do
    [sizes] = doc |> LazyHTML.query(selector) |> LazyHTML.attribute("sizes")
    [width, height] = sizes |> String.split("x") |> Enum.map(&String.to_integer/1)

    {width, height}
  end

  defp png_dimensions(<<_signature::binary-size(8), _length::32, "IHDR", width::32, height::32, _rest::binary>>),
    do: {width, height}

  defp ico_entries(<<0::16-little, 1::16-little, count::16-little, _::binary>> = binary) do
    for index <- 0..(count - 1)//1 do
      offset = 6 + index * 16

      <<_::binary-size(^offset), width, height, palette, _reserved, planes::16-little, bpp::16-little, size::32-little,
        payload_offset::32-little, _::binary>> = binary

      <<_::binary-size(^payload_offset), payload::binary-size(^size), _::binary>> = binary

      %{
        width: if(width == 0, do: 256, else: width),
        height: if(height == 0, do: 256, else: height),
        palette: palette,
        planes: planes,
        bpp: bpp,
        payload: payload
      }
    end
  end
end
