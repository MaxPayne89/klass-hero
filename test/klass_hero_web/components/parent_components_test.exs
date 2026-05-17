defmodule KlassHeroWeb.ParentComponentsTest do
  @moduledoc """
  Phase 2 — `Pa*` parent-surface components.

  Asserts each component renders the bundle's structural contract: sidebar
  active state, kid picker selection markup, stat-card "Coming soon"
  treatment, booking-usage hide-on-unlimited, etc.
  """

  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest

  alias KlassHeroWeb.ParentComponents

  describe "pa_sidebar/1" do
    test "marks the active nav item with aria-current=page", %{} do
      html = render_pa_sidebar(active: :home)

      assert html =~ ~s|aria-current="page"|
      assert html =~ "Dashboard"
      assert html =~ "Bookings"
      assert html =~ "Sessions"
    end

    test "renders the user initials in the desktop avatar", %{} do
      html = render_pa_sidebar(active: :home, user: %{name: "Maxi Pergl", email: "m@example.com"})

      # Initial 'M' appears inside the avatar circle (between the wrapping div tags).
      assert html =~ ~r|font-bold text-black\">\s*M\s*</div>|
      assert html =~ "Maxi Pergl"
    end

    test "renders the mobile bottom-tab nav", %{} do
      html = render_pa_sidebar(active: :messages)

      # Mobile bottom-tab is fixed and only contains the 5 most-tapped items.
      assert html =~ ~s|aria-label="Parent bottom navigation"|
      assert html =~ "fixed bottom-0"
    end

    test "shows 'Coming soon' tooltip for items without an href", %{} do
      html = render_pa_sidebar(active: :home)

      assert html =~ "Planner"
      assert html =~ ~s|title="Coming soon"|
    end

    test "'My Kids' jumps directly to the children list, settings has its own entry", %{} do
      html = render_pa_sidebar(active: :children)

      # 'My Kids' must point at the children list, not the settings hub.
      assert html =~ ~s|href="/family/settings/children"|
      # Settings hub gets its own dedicated nav slot.
      assert html =~ "Settings"
      assert html =~ ~s|href="/family/settings"|
    end
  end

  describe "pa_topbar/1" do
    test "renders title and subtitle on desktop", %{} do
      html = render_pa_topbar(title: "Hi Maxi", subtitle: "Your family this week")

      assert html =~ "Hi Maxi"
      assert html =~ "Your family this week"
    end

    test "renders an optional CTA when label + navigate are set", %{} do
      html =
        render_pa_topbar(title: "Bookings", cta_label: "Book program", cta_navigate: "/bookings")

      assert html =~ "Book program"
      assert html =~ ~s|href="/bookings"|
    end
  end

  describe "pa_kid_picker/1" do
    test "renders one button per kid", %{} do
      kids = [
        %{id: "1", name: "Mila", age: "7", programs: 2, color: "#FFEAC9"},
        %{id: "2", name: "Theo", age: "5", programs: 0, color: "#33CFFF"}
      ]

      html = render_pa_kid_picker(kids: kids, active_id: "1")

      assert html =~ "Mila"
      assert html =~ "Theo"
      # Phoenix renders boolean attrs without ="true"; it appears as bare token.
      assert html =~ ~r|phx-value-id=\"1\"\s+aria-pressed|
    end

    test "renders an add-child button", %{} do
      html = render_pa_kid_picker(kids: [], active_id: nil)

      assert html =~ ~s|aria-label="Add a child"|
    end
  end

  describe "pa_stat_card/1" do
    test "renders title, value, and an icon chip", %{} do
      html =
        render_component(&ParentComponents.pa_stat_card/1, %{
          title: "Active programs",
          value: "3",
          icon: "hero-academic-cap",
          tone: :primary
        })

      assert html =~ "Active programs"
      assert html =~ ">3<"
      assert html =~ "hero-academic-cap"
    end

    test "shows a 'Coming soon' pill when disabled", %{} do
      html =
        render_component(&ParentComponents.pa_stat_card/1, %{
          title: "Messages",
          value: "—",
          icon: "hero-chat-bubble-left-right",
          tone: :cool,
          disabled: true
        })

      assert html =~ "Coming soon"
      assert html =~ "opacity-60"
    end
  end

  describe "pa_upcoming_item/1" do
    test "renders the date block, title, and metadata", %{} do
      session = %{
        month: "MAY",
        day: 12,
        title: "Football Stars",
        time: "16:00",
        kid: "Mila",
        location: "FC Hauptstadt",
        status: :confirmed
      }

      html = render_component(&ParentComponents.pa_upcoming_item/1, %{session: session})

      assert html =~ "MAY"
      assert html =~ ~r|font-extrabold[^>]*>\s*12\s*<|
      assert html =~ "Football Stars"
      assert html =~ "16:00"
      assert html =~ "Mila"
      assert html =~ "FC Hauptstadt"
      assert html =~ "confirmed"
    end
  end

  describe "pa_weekly_goal/1" do
    test "renders the progress bar with correct percent", %{} do
      html = render_component(&ParentComponents.pa_weekly_goal/1, %{goal: 5, done: 3})

      assert html =~ "3 of 5"
      assert html =~ "60%"
      assert html =~ "width: 60%"
    end

    test "shows 'Coming soon' copy when goal is nil", %{} do
      html = render_component(&ParentComponents.pa_weekly_goal/1, %{goal: nil, done: 0})

      assert html =~ "Coming soon"
    end
  end

  describe "pa_message_preview/1" do
    test "renders the empty state when there are no messages", %{} do
      html = render_component(&ParentComponents.pa_message_preview/1, %{messages: []})

      assert html =~ "No messages yet."
    end

    test "renders one row per message with unread dot", %{} do
      msgs = [
        %{id: "a", from: "Anna K.", preview: "Hi!", time: "2m", unread?: true, color: "#FFEAC9"}
      ]

      html = render_component(&ParentComponents.pa_message_preview/1, %{messages: msgs})

      assert html =~ "Anna K."
      assert html =~ "Hi!"
      assert html =~ "2m"
      assert html =~ ~s|aria-label="Unread"|
    end
  end

  describe "pa_family_program_card/1" do
    test "renders title, category, kid avatars and provider", %{} do
      program = %{
        id: "1",
        title: "Code Camp",
        category: "Tech",
        next: "Mon 14:00",
        provider: "CodeKids Berlin",
        status: :active,
        kids: [%{name: "Mila", color: "#FFEAC9"}]
      }

      html = render_component(&ParentComponents.pa_family_program_card/1, %{program: program})

      assert html =~ "Code Camp"
      assert html =~ "Tech"
      assert html =~ "Mon 14:00"
      assert html =~ "CodeKids Berlin"
    end
  end

  describe "pa_booking_usage/1" do
    test "renders the meter when cap is integer", %{} do
      html =
        render_component(&ParentComponents.pa_booking_usage/1, %{
          tier: :explorer,
          used: 3,
          cap: 5
        })

      assert html =~ "Monthly booking usage"
      assert html =~ ~r|font-extrabold[^>]*>\s*2\s*</span>|
      assert html =~ "explorer"
    end

    test "renders nothing when cap is :unlimited", %{} do
      html =
        render_component(&ParentComponents.pa_booking_usage/1, %{
          tier: :active,
          used: 99,
          cap: :unlimited
        })

      refute html =~ "Monthly booking usage"
    end
  end

  ## ------------------------------------------------------------------ helpers

  defp render_pa_sidebar(opts) do
    assigns = %{
      active: Keyword.fetch!(opts, :active),
      user: Keyword.get(opts, :user, %{name: "Test User", email: "test@example.com"})
    }

    rendered_to_string(~H"""
    <ParentComponents.pa_sidebar active={@active} user={@user} />
    """)
  end

  defp render_pa_topbar(opts) do
    assigns = %{
      title: Keyword.fetch!(opts, :title),
      subtitle: Keyword.get(opts, :subtitle),
      cta_label: Keyword.get(opts, :cta_label),
      cta_navigate: Keyword.get(opts, :cta_navigate),
      user: Keyword.get(opts, :user, %{name: "Test User", email: "test@example.com"})
    }

    rendered_to_string(~H"""
    <ParentComponents.pa_topbar
      title={@title}
      subtitle={@subtitle}
      cta_label={@cta_label}
      cta_navigate={@cta_navigate}
      user={@user}
    />
    """)
  end

  defp render_pa_kid_picker(opts) do
    assigns = %{
      kids: Keyword.fetch!(opts, :kids),
      active_id: Keyword.get(opts, :active_id)
    }

    rendered_to_string(~H"""
    <ParentComponents.pa_kid_picker kids={@kids} active_id={@active_id} />
    """)
  end
end
