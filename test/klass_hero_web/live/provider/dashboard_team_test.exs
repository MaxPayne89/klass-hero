defmodule KlassHeroWeb.Provider.DashboardTeamTest do
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias KlassHero.Provider
  alias KlassHero.Provider.PayRate
  alias KlassHero.ProviderFixtures

  setup :register_and_log_in_provider

  describe "empty state" do
    test "shows empty state message when no staff members exist", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      assert has_element?(view, "#team-members-empty")
    end

    test "shows 'Add Team Member' button", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      assert has_element?(view, "#add-member-btn")
    end
  end

  describe "member cards" do
    test "displays staff member card when members exist", %{conn: conn, provider: provider} do
      ProviderFixtures.staff_member_fixture(
        provider_id: provider.id,
        first_name: "Alice",
        last_name: "Smith",
        role: "Head Coach"
      )

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      html = render(view)
      assert html =~ "Alice Smith"
      assert html =~ "Head Coach"
    end

    test "displays multiple staff member cards", %{conn: conn, provider: provider} do
      ProviderFixtures.staff_member_fixture(
        provider_id: provider.id,
        first_name: "Alice",
        last_name: "Smith"
      )

      ProviderFixtures.staff_member_fixture(
        provider_id: provider.id,
        first_name: "Bob",
        last_name: "Jones"
      )

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      html = render(view)
      assert html =~ "Alice Smith"
      assert html =~ "Bob Jones"
    end

    test "shows tags as pills on member card", %{conn: conn, provider: provider} do
      ProviderFixtures.staff_member_fixture(
        provider_id: provider.id,
        first_name: "Alice",
        last_name: "Smith",
        tags: ["sports", "arts"]
      )

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      html = render(view)
      assert html =~ "sports"
      assert html =~ "arts"
    end

    test "shows qualifications on member card", %{conn: conn, provider: provider} do
      ProviderFixtures.staff_member_fixture(
        provider_id: provider.id,
        first_name: "Alice",
        last_name: "Smith",
        qualifications: ["First Aid", "UEFA B"]
      )

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      html = render(view)
      assert html =~ "First Aid"
      assert html =~ "UEFA B"
    end
  end

  describe "add member flow" do
    test "clicking 'Add Team Member' opens the form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      refute has_element?(view, "#staff-member-form")

      view |> element("#add-member-btn") |> render_click()

      assert has_element?(view, "#staff-member-form")
      assert has_element?(view, "#staff-form")
    end

    test "form submission creates a new staff member", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      view |> element("#add-member-btn") |> render_click()

      view
      |> form("#staff-form", %{
        "staff_member_schema" => %{
          "first_name" => "Charlie",
          "last_name" => "Brown",
          "role" => "Assistant Coach"
        }
      })
      |> render_submit()

      # Form should close after successful save
      refute has_element?(view, "#staff-member-form")

      # Flash should indicate success
      assert render(view) =~ "Team member added."
    end

    test "closing the form hides it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      view |> element("#add-member-btn") |> render_click()
      assert has_element?(view, "#staff-member-form")

      # Use the Cancel button text to disambiguate from the X close button
      view |> element("#staff-member-form button", "Cancel") |> render_click()
      refute has_element?(view, "#staff-member-form")
    end
  end

  describe "edit member flow" do
    test "clicking Edit opens pre-filled form", %{conn: conn, provider: provider} do
      staff =
        ProviderFixtures.staff_member_fixture(
          provider_id: provider.id,
          first_name: "Alice",
          last_name: "Smith",
          role: "Coach"
        )

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      view
      |> element(~s(button[phx-click="edit_member"][phx-value-id="#{staff.id}"]))
      |> render_click()

      assert has_element?(view, "#staff-member-form")
      html = render(view)
      assert html =~ "Edit Team Member"
    end

    test "saving edits updates the member", %{conn: conn, provider: provider} do
      staff =
        ProviderFixtures.staff_member_fixture(
          provider_id: provider.id,
          first_name: "Alice",
          last_name: "Smith",
          role: "Coach"
        )

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      view
      |> element(~s(button[phx-click="edit_member"][phx-value-id="#{staff.id}"]))
      |> render_click()

      view
      |> form("#staff-form", %{
        "staff_member_schema" => %{
          "role" => "Head Coach"
        }
      })
      |> render_submit()

      assert render(view) =~ "Team member updated."
    end
  end

  describe "delete member" do
    test "deleting a member shows success flash", %{conn: conn, provider: provider} do
      staff =
        ProviderFixtures.staff_member_fixture(
          provider_id: provider.id,
          first_name: "Alice",
          last_name: "Smith"
        )

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      html = render(view)
      assert html =~ "Alice Smith"

      view
      |> element(~s(button[phx-click="delete_member"][phx-value-id="#{staff.id}"]))
      |> render_click()

      assert render(view) =~ "Team member removed."
    end
  end

  describe "form validation" do
    test "validates on change and keeps form visible", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      view |> element("#add-member-btn") |> render_click()

      view
      |> form("#staff-form", %{
        "staff_member_schema" => %{
          "first_name" => "",
          "last_name" => ""
        }
      })
      |> render_change()

      # Form should still be visible after validation
      assert has_element?(view, "#staff-member-form")
    end

    test "shows inline validation errors on create submit", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      view |> element("#add-member-btn") |> render_click()

      view
      |> form("#staff-form", %{
        "staff_member_schema" => %{
          "first_name" => "",
          "last_name" => ""
        }
      })
      |> render_submit()

      # Form stays open with error flash
      assert has_element?(view, "#staff-member-form")
      assert render(view) =~ "Please fix the errors below."

      # Inline errors render (phx-feedback-for removes hidden class when action is set)
      assert render(view) =~ "can&#39;t be blank"
    end

    test "shows inline validation errors on update submit", %{conn: conn, provider: provider} do
      staff =
        ProviderFixtures.staff_member_fixture(
          provider_id: provider.id,
          first_name: "Alice",
          last_name: "Smith"
        )

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      view
      |> element(~s(button[phx-click="edit_member"][phx-value-id="#{staff.id}"]))
      |> render_click()

      view
      |> form("#staff-form", %{
        "staff_member_schema" => %{
          "first_name" => "",
          "last_name" => ""
        }
      })
      |> render_submit()

      # Form stays open with error flash
      assert has_element?(view, "#staff-member-form")
      assert render(view) =~ "Please fix the errors below."

      # Inline errors render
      assert render(view) =~ "can&#39;t be blank"
    end

    test "error flash is cleared on successful create", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      # Trigger validation error first
      view |> element("#add-member-btn") |> render_click()

      view
      |> form("#staff-form", %{
        "staff_member_schema" => %{
          "first_name" => "",
          "last_name" => ""
        }
      })
      |> render_submit()

      assert render(view) =~ "Please fix the errors below."

      # Now submit valid data
      view
      |> form("#staff-form", %{
        "staff_member_schema" => %{
          "first_name" => "Valid",
          "last_name" => "Name"
        }
      })
      |> render_submit()

      html = render(view)
      assert html =~ "Team member added."
      refute html =~ "Please fix the errors below."
    end

    test "no qualifications cast error when save fails with validation error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      view |> element("#add-member-btn") |> render_click()

      # Submit with qualifications string but missing required first/last name
      html =
        view
        |> form("#staff-form", %{
          "staff_member_schema" => %{
            "first_name" => "",
            "last_name" => "",
            "qualifications" => "First Aid, CPR"
          }
        })
        |> render_submit()

      # Qualifications should not show cast error — the string was normalized to a list
      refute html =~ "is invalid"
      # Actual validation errors should appear
      assert html =~ "Please fix the errors below."
    end

    test "validates qualifications as comma-separated string without cast error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      view |> element("#add-member-btn") |> render_click()

      html =
        view
        |> form("#staff-form", %{
          "staff_member_schema" => %{
            "first_name" => "Alice",
            "last_name" => "Smith",
            "qualifications" => "First Aid, CPR"
          }
        })
        |> render_change()

      # No cast error on qualifications — the comma string was parsed to a list
      refute html =~ "is invalid"
      assert has_element?(view, "#staff-member-form")
    end
  end

  describe "pay rate flow" do
    alias KlassHero.Provider

    test "form submission with an hourly rate persists the rate", %{conn: conn, provider: provider} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      view |> element("#add-member-btn") |> render_click()

      view
      |> form("#staff-form", %{
        "staff_member_schema" => %{
          "first_name" => "Rena",
          "last_name" => "Ratepayer",
          "rate_type" => "hourly",
          "rate_amount" => "25.00",
          "rate_currency" => "EUR"
        }
      })
      |> render_submit()

      refute has_element?(view, "#staff-member-form")

      {:ok, [staff]} = Provider.list_staff_members(provider.id)
      assert staff.pay_rate.type == :hourly
      assert Decimal.equal?(staff.pay_rate.money.amount, Decimal.new("25.00"))
      assert staff.pay_rate.money.currency == :EUR
    end

    test "form submission with per_session rate persists the rate", %{conn: conn, provider: provider} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      view |> element("#add-member-btn") |> render_click()

      view
      |> form("#staff-form", %{
        "staff_member_schema" => %{
          "first_name" => "Sonia",
          "last_name" => "Session",
          "rate_type" => "per_session",
          "rate_amount" => "80.00",
          "rate_currency" => "EUR"
        }
      })
      |> render_submit()

      {:ok, [staff]} = Provider.list_staff_members(provider.id)
      assert staff.pay_rate.type == :per_session
    end

    test "form submission without rate_type leaves pay_rate as nil", %{conn: conn, provider: provider} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      view |> element("#add-member-btn") |> render_click()

      view
      |> form("#staff-form", %{
        "staff_member_schema" => %{
          "first_name" => "No",
          "last_name" => "Rate",
          "rate_type" => "",
          "rate_amount" => ""
        }
      })
      |> render_submit()

      {:ok, [staff]} = Provider.list_staff_members(provider.id)
      assert is_nil(staff.pay_rate)
    end

    test "editing can clear an existing rate back to nil", %{conn: conn, provider: provider} do
      {:ok, pay_rate} = PayRate.hourly(Decimal.new("25.00"))

      staff =
        ProviderFixtures.staff_member_fixture(
          provider_id: provider.id,
          first_name: "Carla",
          last_name: "Clear",
          pay_rate: pay_rate
        )

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      view
      |> element(~s(button[phx-click="edit_member"][phx-value-id="#{staff.id}"]))
      |> render_click()

      view
      |> form("#staff-form", %{
        "staff_member_schema" => %{
          "first_name" => "Carla",
          "last_name" => "Clear",
          "rate_type" => "",
          "rate_amount" => ""
        }
      })
      |> render_submit()

      {:ok, updated} = Provider.get_staff_member(staff.id)
      assert is_nil(updated.pay_rate)
    end

    test "invalid rate_amount keeps the form open with a field error", %{conn: conn, provider: provider} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      view |> element("#add-member-btn") |> render_click()

      html =
        view
        |> form("#staff-form", %{
          "staff_member_schema" => %{
            "first_name" => "Bad",
            "last_name" => "Amount",
            "rate_type" => "hourly",
            "rate_amount" => "abc"
          }
        })
        |> render_submit()

      # Form stays open (didn't save)
      assert has_element?(view, "#staff-member-form")
      assert html =~ "is invalid"
      assert Provider.list_staff_members(provider.id) == {:ok, []}
    end

    test "editing an unrelated field preserves an existing pay rate", %{conn: conn, provider: provider} do
      {:ok, pay_rate} = PayRate.hourly(Decimal.new("25.00"))

      staff =
        ProviderFixtures.staff_member_fixture(
          provider_id: provider.id,
          first_name: "Pia",
          last_name: "Preserve",
          role: "Coach",
          pay_rate: pay_rate
        )

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      view
      |> element(~s(button[phx-click="edit_member"][phx-value-id="#{staff.id}"]))
      |> render_click()

      # Form should render pre-populated with the existing rate — submit only a
      # role change and the pre-populated rate fields flow through unchanged.
      view
      |> form("#staff-form", %{"staff_member_schema" => %{"role" => "Head Coach"}})
      |> render_submit()

      {:ok, updated} = Provider.get_staff_member(staff.id)
      assert updated.role == "Head Coach"
      assert updated.pay_rate.type == :hourly
      assert Decimal.equal?(updated.pay_rate.money.amount, Decimal.new("25.00"))
    end
  end
end
