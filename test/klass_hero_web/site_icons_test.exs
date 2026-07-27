defmodule KlassHeroWeb.SiteIconsTest do
  @moduledoc """
  Covers the site-icon surface: the `<link>` declarations in the root layout,
  that the referenced files are actually served, and that `favicon.ico` is
  structurally sound.

  On what these tests are and are not worth (see #1159):

  The markup and reachability tests would have **passed** the whole time the
  favicon was broken — the tag and the route were always fine, the *pixels* were
  not. They are genuine regression cover for a different failure: someone edits
  the root layout and drops a tag, or renames an asset. They do not validate the
  original fix.

  The `favicon.ico` structure test is the one that encodes the actual root cause.
  The shipped icon had a paletted 8bpp entry at 32x32 whose 1-bit AND mask
  clipped every antialiased stroke — and 32x32 is exactly what Chrome requests
  on a 2x display. Asserting 32bpp truecolour PNG payloads makes that
  unshippable again.
  """
  use KlassHeroWeb.ConnCase, async: true

  @favicon Path.join([:code.priv_dir(:klass_hero), "static", "favicon.ico"])
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
        <<_signature::binary-size(8), _length::32, "IHDR", width::32, height::32, _rest::binary>> =
          entry.payload

        assert {width, height} == {entry.width, entry.height},
               "directory claims #{entry.width}x#{entry.height} but the PNG is #{width}x#{height}"
      end
    end
  end

  # `~p` appends a cache-busting query (`?vsn=d`) to known static paths, so
  # compare on the path alone.
  defp icon_hrefs(doc, selector) do
    doc
    |> LazyHTML.query(selector)
    |> LazyHTML.attribute("href")
    |> Enum.map(&(&1 |> String.split("?") |> hd()))
  end

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
