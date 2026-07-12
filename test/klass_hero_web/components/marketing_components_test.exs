defmodule KlassHeroWeb.MarketingComponentsTest do
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest

  alias KlassHero.Accounts.Scope
  alias KlassHero.Accounts.User
  alias KlassHeroWeb.MarketingComponents

  describe "mk_header/1 — anonymous" do
    test "shows Sign in + Sign up CTAs and no dashboard CTA" do
      html = render_mk_header(current_scope: nil)

      assert html =~ "Sign in"
      assert html =~ "Sign up"
      refute html =~ "Go to dashboard"
    end
  end

  describe "mk_header/1 — signed-in parent" do
    test "shows a single primary 'Go to dashboard' CTA" do
      html = render_mk_header(current_scope: scope_for(:parent))

      assert html =~ "Go to dashboard"
      assert html =~ ~s|href="/dashboard"|
    end

    test "drops the Settings and Log out chips from the header" do
      html = render_mk_header(current_scope: scope_for(:parent))

      refute html =~ ~s|href="/users/settings"|
      refute html =~ ~s|href="/users/log-out"|
    end

    test "drops Sign in / Sign up CTAs" do
      html = render_mk_header(current_scope: scope_for(:parent))

      refute html =~ "Sign in"
      refute html =~ "Sign up"
    end

    test "mobile sheet shows the email and a single primary CTA" do
      html = render_mk_header(current_scope: scope_for(:parent))

      assert html =~ "parent@example.com"
      assert html =~ "Signed in as"
      # Single Go-to-dashboard appears in both desktop + mobile branch — count == 2
      assert count_substr(html, "Go to dashboard") == 2
    end
  end

  describe "mk_header/1 — signed-in provider" do
    test "Go to dashboard CTA links to the provider dashboard" do
      html = render_mk_header(current_scope: scope_for(:provider))

      assert html =~ ~s|href="/provider/dashboard"|
      assert html =~ "Go to dashboard"
    end
  end

  describe "vetting_steps/0" do
    @expected_titles [
      "Identity & Age Verification",
      "Experience Validation",
      "Extended Background Checks",
      "Video Screening",
      "Child Safeguarding Training",
      "Community Standards Agreement"
    ]

    test "returns the six vetting steps in order, each a full icon/title/description map" do
      steps = MarketingComponents.vetting_steps()

      assert length(steps) == 6
      assert Enum.map(steps, & &1.title) == @expected_titles

      for step <- steps do
        assert %{icon: "hero-" <> _, title: title, description: desc} = step
        assert is_binary(title) and title != ""
        assert is_binary(desc) and desc != ""
      end
    end
  end

  defp render_mk_header(opts) do
    assigns = %{
      current_scope: Keyword.get(opts, :current_scope),
      active: Keyword.get(opts, :active, :home),
      locale: Keyword.get(opts, :locale, "en")
    }

    rendered_to_string(~H"""
    <MarketingComponents.mk_header
      active={@active}
      current_scope={@current_scope}
      locale={@locale}
    />
    """)
  end

  defp scope_for(:parent) do
    %Scope{
      user: %User{
        id: 1,
        email: "parent@example.com",
        name: "Parent User",
        intended_roles: [:parent]
      }
    }
  end

  defp scope_for(:provider) do
    %Scope{
      user: %User{
        id: 2,
        email: "provider@example.com",
        name: "Provider User",
        intended_roles: [:provider]
      }
    }
  end

  defp count_substr(haystack, needle) do
    haystack |> String.split(needle) |> length() |> Kernel.-(1)
  end
end
