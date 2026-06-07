defmodule KlassHeroWeb.UserLive.RegistrationTierTest do
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "registration without tier selection" do
    # Provider tiers removed (ADR-0004): no plan choice at signup
    test "never shows a tier selector, even with provider role checked", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/register")

      refute has_element?(view, "#tier-selector")

      view
      |> form("#registration_form", %{
        "user" => %{
          "name" => "Test",
          "email" => "test@example.com",
          "intended_roles" => ["provider"]
        }
      })
      |> render_change()

      refute has_element?(view, "#tier-selector")
    end
  end
end
