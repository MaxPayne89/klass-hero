defmodule KlassHeroWeb.FlashVisibilityTest do
  @moduledoc """
  Regression tests for flash message visibility.

  Issue #232: Flash popups were hidden under the navbar because <main> had
  `relative z-0`, creating a CSS stacking context that trapped the flash's
  z-50 below the navbar's z-10.
  """
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.AccountsFixtures
  import Phoenix.LiveViewTest

  describe "flash visibility in layout" do
    test "flash-group container is present in layout", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#flash-group")
    end

    test "main element does not create a stacking context that traps flash z-index", %{
      conn: conn
    } do
      {:ok, _view, html} = live(conn, ~p"/")

      # Trigger: stacking context bug caused <main class="... z-0"> to trap fixed flash
      # Why: z-0 on main creates stacking context, confining flash z-50 below navbar z-10
      # Outcome: regression guard — if z-0 is re-added to main, this test fails
      refute html =~ ~r/<main[^>]*\bz-0\b/
    end

    test "info flash renders in DOM when flash is set", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      # Magic link is now the secondary method — toggle to it first
      lv |> element("button", "Or use magic link") |> render_click()

      {:ok, view, _html} =
        form(lv, "#login_form_magic", user: %{email: user.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert has_element?(view, "#flash-info")
    end
  end
end
