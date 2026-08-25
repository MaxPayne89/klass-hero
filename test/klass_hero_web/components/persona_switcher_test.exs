defmodule KlassHeroWeb.PersonaSwitcherTest do
  @moduledoc """
  The switcher inside `kh_user_menu` (#899).

  It lives there because that menu is the only component both the parent and the
  provider chrome render, and both render it twice — desktop and mobile — so the
  switcher is reachable on a phone without a second component.
  """
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest

  alias KlassHeroWeb.UIComponents

  defp render_switcher(personas, active_persona) do
    assigns = %{personas: personas, active_persona: active_persona}

    rendered_to_string(~H"""
    <UIComponents.persona_switcher personas={@personas} active_persona={@active_persona} />
    """)
  end

  describe "when there is nothing to switch between" do
    # Almost every account holds one persona. An inert control naming your own
    # single role is noise, so it renders nothing at all.
    test "renders nothing for a single persona" do
      assert render_switcher([:parent], :parent) =~ ~r/\A\s*\z/
    end

    test "renders nothing for no personas" do
      assert render_switcher([], nil) =~ ~r/\A\s*\z/
    end
  end

  describe "when the account holds several personas" do
    test "offers the others and not the one already being viewed" do
      html = render_switcher([:parent, :provider], :parent)

      assert html =~ "/users/persona/provider"
      refute html =~ "/users/persona/parent"
    end

    test "names the persona currently being viewed" do
      assert render_switcher([:parent, :provider], :provider) =~ "Provider"
      assert render_switcher([:parent, :provider], :parent) =~ "Parent"
    end

    test "offers every other persona for a three-persona account" do
      html = render_switcher([:parent, :provider, :staff], :provider)

      assert html =~ "/users/persona/parent"
      assert html =~ "/users/persona/staff"
      refute html =~ "/users/persona/provider"
    end

    # Only the plug pipeline can write the session, so a GET link — or a
    # LiveView event — would leave the choice to vanish on the next request.
    test "each entry is a POST" do
      html = render_switcher([:parent, :provider], :parent)

      assert html =~ ~s|data-method="post"|
    end
  end
end
