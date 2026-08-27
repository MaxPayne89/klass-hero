defmodule KlassHeroWeb.ParticipationComponentsTest do
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias KlassHeroWeb.ParticipationComponents

  describe "participation_status/1" do
    test "renders :cancelled with red badge and x-circle icon" do
      html =
        render_component(&ParticipationComponents.participation_status/1,
          status: :cancelled,
          size: :sm
        )

      assert html =~ "bg-red-100"
      assert html =~ "hero-x-circle"
      assert html =~ "Cancelled"
    end
  end

  describe "participation_card/1 — Session Capacity" do
    setup do
      %{
        session:
          KlassHero.Factory.build(:program_session,
            status: :scheduled,
            max_capacity: nil
          )
      }
    end

    test "shows the roster against the Session Capacity when one is set", %{session: session} do
      html =
        render_component(&ParticipationComponents.participation_card/1,
          session: %{session | max_capacity: 5},
          role: :provider,
          attendance: %{roster: 4, checked_in: 0}
        )

      assert html =~ "4 of 5"
    end

    test "renders the plain count when the session is uncapped", %{session: session} do
      html =
        render_component(&ParticipationComponents.participation_card/1,
          session: session,
          role: :provider,
          attendance: %{roster: 4, checked_in: 0}
        )

      assert html =~ "4 children enrolled"
      refute html =~ "data-occupancy"
    end

    test "marks a session whose roster exceeds its Session Capacity", %{session: session} do
      html =
        render_component(&ParticipationComponents.participation_card/1,
          session: %{session | max_capacity: 5},
          role: :provider,
          attendance: %{roster: 6, checked_in: 0}
        )

      assert html =~ ~s(data-occupancy="over")
      assert html =~ "Over capacity"
    end

    test "does not mark a session sitting exactly at its Session Capacity", %{session: session} do
      html =
        render_component(&ParticipationComponents.participation_card/1,
          session: %{session | max_capacity: 5},
          role: :provider,
          attendance: %{roster: 5, checked_in: 0}
        )

      refute html =~ "Over capacity"
    end
  end
end
