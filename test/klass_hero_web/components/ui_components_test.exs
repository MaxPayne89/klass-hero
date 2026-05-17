defmodule KlassHeroWeb.UIComponentsTest do
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest

  alias KlassHeroWeb.UIComponents

  describe "kh_logo/1" do
    test "renders the primary logo by default" do
      html = render_component(&UIComponents.kh_logo/1, %{})

      assert html =~ ~s|src="/images/logo.png"|
      assert html =~ ~s|alt="Klass Hero"|
      assert html =~ ~s|height="32"|
    end

    test "renders the white variant when variant=:white" do
      html = render_component(&UIComponents.kh_logo/1, %{variant: :white})

      assert html =~ ~s|src="/images/logo-white-large.png"|
    end

    test "honours the size attr" do
      html = render_component(&UIComponents.kh_logo/1, %{size: 26})

      assert html =~ ~s|height="26"|
    end

    test "passes through extra classes" do
      html = render_component(&UIComponents.kh_logo/1, %{class: "shrink-0"})

      assert html =~ "shrink-0"
    end
  end

  describe "kh_button/1" do
    test "renders a primary button by default" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <UIComponents.kh_button>Book program</UIComponents.kh_button>
        """)

      assert html =~ "Book program"
      assert html =~ ~s|type="button"|
      assert html =~ "bg-[var(--brand-primary)]"
    end

    test "honours the variant attr" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <UIComponents.kh_button variant={:dark}>Continue</UIComponents.kh_button>
        """)

      assert html =~ "bg-black"
      assert html =~ "Continue"
    end

    test "honours size :sm" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <UIComponents.kh_button size={:sm}>Save</UIComponents.kh_button>
        """)

      assert html =~ "text-sm"
      assert html =~ "rounded-lg"
    end

    test "renders an icon when provided" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <UIComponents.kh_button icon="hero-plus">Add</UIComponents.kh_button>
        """)

      assert html =~ "hero-plus"
    end

    test "passes phx-click through" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <UIComponents.kh_button phx-click="save">Save</UIComponents.kh_button>
        """)

      assert html =~ ~s|phx-click="save"|
    end
  end

  describe "kh_list_row/1" do
    test "renders the title slot" do
      html = render_kh_list_row(%{}, title: "Football Stars")

      assert html =~ "Football Stars"
    end

    test "renders dot-separated meta items" do
      html = render_kh_list_row(%{meta: ["a", "b", "c"]}, title: "T")

      assert count_substr(html, "·") == 2
    end

    test "renders single string meta as one item with no dots" do
      html = render_kh_list_row(%{meta: "Just one"}, title: "T")

      assert html =~ "Just one"
      assert count_substr(html, "·") == 0
    end

    test "renders stats with value and label" do
      html =
        render_kh_list_row(
          %{stats: [%{value: "12/20", label: "booked"}, %{value: "€45", label: "/mo"}]},
          title: "T"
        )

      assert html =~ "12/20"
      assert html =~ "booked"
      assert html =~ "€45"
    end

    test "applies compact density classes" do
      html = render_kh_list_row(%{density: :compact}, title: "T")

      assert html =~ "p-2.5"
    end

    test "applies hover class only when hover=true" do
      hover = render_kh_list_row(%{hover: true}, title: "T")
      no_hover = render_kh_list_row(%{hover: false}, title: "T")

      assert hover =~ "hover:bg-"
      refute no_hover =~ "hover:bg-"
    end

    test "renders the footer slot when provided" do
      html = render_kh_list_row(%{}, title: "T", footer: "decline-accept-bar")

      assert html =~ "decline-accept-bar"
    end
  end

  describe "kh_card/1 alias" do
    test "renders default variant" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <UIComponents.kh_card>hi</UIComponents.kh_card>
        """)

      assert html =~ "hi"
      assert html =~ "rounded-2xl"
    end

    test "renders dark variant" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <UIComponents.kh_card variant={:dark}>hi</UIComponents.kh_card>
        """)

      assert html =~ "bg-black"
    end

    test "renders soft variant" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <UIComponents.kh_card variant={:soft}>hi</UIComponents.kh_card>
        """)

      assert html =~ "hi"
    end
  end

  describe "kh_pill/1 alias" do
    test "renders outline tone by default" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <UIComponents.kh_pill>Pending</UIComponents.kh_pill>
        """)

      assert html =~ "Pending"
      assert html =~ "rounded-full"
    end

    test "renders dark tone" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <UIComponents.kh_pill tone={:dark}>Verified</UIComponents.kh_pill>
        """)

      assert html =~ "bg-black"
      assert html =~ "text-white"
    end

    test "renders cream tone" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <UIComponents.kh_pill tone={:cream}>Draft</UIComponents.kh_pill>
        """)

      assert html =~ "Draft"
    end

    test "renders accent tone" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <UIComponents.kh_pill tone={:accent}>New</UIComponents.kh_pill>
        """)

      assert html =~ "New"
    end
  end

  describe "kh_icon/1 alias" do
    test "renders a heroicon" do
      html = render_component(&UIComponents.kh_icon/1, %{name: "hero-bell"})

      assert html =~ "hero-bell"
    end
  end

  describe "kh_icon_chip/1 alias" do
    test "renders with a named gradient" do
      html =
        render_component(&UIComponents.kh_icon_chip/1, %{
          icon: "hero-academic-cap",
          gradient: :primary
        })

      assert html =~ "hero-academic-cap"
    end
  end

  describe "messages_indicator/1" do
    test "renders with default href to /messages" do
      html =
        render_component(&UIComponents.messages_indicator/1, %{
          unread_count: 0
        })

      assert html =~ ~s|href="/messages"|
    end

    test "renders with custom href" do
      html =
        render_component(&UIComponents.messages_indicator/1, %{
          unread_count: 0,
          href: ~p"/provider/messages"
        })

      assert html =~ ~s|href="/provider/messages"|
    end

    test "renders unread badge when count > 0" do
      html =
        render_component(&UIComponents.messages_indicator/1, %{
          unread_count: 5
        })

      assert html =~ "5"
    end

    test "caps unread badge at 99" do
      html =
        render_component(&UIComponents.messages_indicator/1, %{
          unread_count: 150
        })

      assert html =~ "99"
    end

    test "hides badge when unread count is 0" do
      html =
        render_component(&UIComponents.messages_indicator/1, %{
          unread_count: 0
        })

      refute html =~ "badge" or html =~ "bg-rose"
    end
  end

  # --- helpers --------------------------------------------------------------

  defp render_kh_list_row(opts, slots) do
    assigns = %{
      density: Map.get(opts, :density, :comfortable),
      hover: Map.get(opts, :hover, false),
      meta: Map.get(opts, :meta),
      stats: Map.get(opts, :stats),
      class: Map.get(opts, :class, ""),
      title_text: Keyword.fetch!(slots, :title),
      footer_text: Keyword.get(slots, :footer)
    }

    rendered_to_string(~H"""
    <UIComponents.kh_list_row
      density={@density}
      hover={@hover}
      meta={@meta}
      stats={@stats}
      class={@class}
    >
      <:title>{@title_text}</:title>
      <:footer :if={@footer_text}>{@footer_text}</:footer>
    </UIComponents.kh_list_row>
    """)
  end

  describe "admin_nav/1" do
    test "renders Admin heading + Dashboard + Verifications links when user is admin" do
      html = render_admin_nav(is_admin: true)

      assert html =~ "Admin"
      assert html =~ ~s|href="/admin/accounts"|
      assert html =~ ~s|href="/admin/verifications"|
      assert html =~ "Dashboard"
      assert html =~ "Verifications"
    end

    test "renders nothing when user is not admin" do
      html = render_admin_nav(is_admin: false)

      refute html =~ ~s|href="/admin/accounts"|
      refute html =~ ~s|href="/admin/verifications"|
    end

    test "uses menuitem role for admin links (a11y)" do
      html = render_admin_nav(is_admin: true)

      assert html =~ ~s|role="menuitem"|
    end
  end

  describe "kh_user_menu/1" do
    test "renders the trigger as initial-circle from user.name" do
      html = render_kh_user_menu(user: %{name: "Maxi", email: "max@example.com"})

      assert html =~ ~s|id="user-menu-trigger"|
      assert html =~ ~s|aria-haspopup="menu"|
      assert html =~ ~s|aria-expanded="false"|
      assert html =~ "rounded-full"
      assert html =~ ~r/<button[^>]*>\s*M\s*</
    end

    test "falls back to email initial when name is nil" do
      html = render_kh_user_menu(user: %{name: nil, email: "alice@example.com"})

      assert html =~ ~r/<button[^>]*>\s*A\s*</
    end

    test "falls back to '?' when both name and email are nil" do
      html = render_kh_user_menu(user: %{name: nil, email: nil})

      assert html =~ ~r/<button[^>]*>\s*\?\s*</
    end

    test "renders the dropdown panel hidden by default" do
      html = render_kh_user_menu(user: %{name: "Maxi", email: "max@example.com"})

      assert html =~ ~s|id="user-menu-panel"|
      assert html =~ ~s|class="hidden absolute right-0|
      assert html =~ ~s|role="menu"|
    end

    test "renders Settings link to /users/settings" do
      html = render_kh_user_menu(user: %{name: "Maxi", email: "max@example.com"})

      assert html =~ ~s|href="/users/settings"|
      assert html =~ "Settings"
    end

    test "renders Log out link to /users/log-out with method=delete" do
      html = render_kh_user_menu(user: %{name: "Maxi", email: "max@example.com"})

      assert html =~ ~s|href="/users/log-out"|
      assert html =~ ~s|data-method="delete"|
      assert html =~ "Log out"
    end

    test "shows the user's email in the dropdown header" do
      html = render_kh_user_menu(user: %{name: "Maxi", email: "max@example.com"})

      assert html =~ "max@example.com"
    end

    test "wires the click-away backdrop with the matching id" do
      html = render_kh_user_menu(user: %{name: "Maxi", email: "max@example.com"})

      assert html =~ ~s|id="user-menu-backdrop"|
      assert html =~ ~s|class="hidden fixed inset-0 z-30"|
    end

    test "supports multiple instances on one page via distinct ids" do
      assigns = %{user: %{name: "Maxi", email: "max@example.com"}}

      html =
        rendered_to_string(~H"""
        <UIComponents.kh_user_menu user={@user} id="desktop" />
        <UIComponents.kh_user_menu user={@user} id="mobile" />
        """)

      assert html =~ ~s|id="desktop-trigger"|
      assert html =~ ~s|id="desktop-panel"|
      assert html =~ ~s|id="mobile-trigger"|
      assert html =~ ~s|id="mobile-panel"|
    end

    test "embeds admin links when user.is_admin is true" do
      html =
        render_kh_user_menu(user: %{name: "A", email: "admin@example.com", is_admin: true})

      assert html =~ ~s|href="/admin/accounts"|
      assert html =~ ~s|href="/admin/verifications"|
    end

    test "omits admin links when user.is_admin is false" do
      html =
        render_kh_user_menu(user: %{name: "P", email: "parent@example.com", is_admin: false})

      refute html =~ ~s|href="/admin/accounts"|
      refute html =~ ~s|href="/admin/verifications"|
    end
  end

  defp render_admin_nav(opts) do
    assigns = %{is_admin: Keyword.fetch!(opts, :is_admin)}

    rendered_to_string(~H"""
    <UIComponents.admin_nav is_admin={@is_admin} />
    """)
  end

  defp render_kh_user_menu(opts) do
    assigns = %{
      user: Keyword.fetch!(opts, :user),
      id: Keyword.get(opts, :id, "user-menu")
    }

    rendered_to_string(~H"""
    <UIComponents.kh_user_menu user={@user} id={@id} />
    """)
  end

  defp count_substr(haystack, needle) do
    haystack |> String.split(needle) |> length() |> Kernel.-(1)
  end
end
