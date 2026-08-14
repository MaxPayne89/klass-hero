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

  describe "end employment" do
    setup %{provider: provider} do
      staff =
        ProviderFixtures.staff_member_fixture(
          provider_id: provider.id,
          first_name: "Alice",
          last_name: "Smith"
        )

      %{staff: staff}
    end

    test "moves the member out of the roster and into former team members", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/provider/dashboard/team")

      assert has_element?(view, "#team_members-#{ctx.staff.id}")

      view |> element("#end-employment-#{ctx.staff.id}") |> render_click()

      refute has_element?(view, "#team_members-#{ctx.staff.id}")
      assert has_element?(view, "#former_members-#{ctx.staff.id}")
    end

    test "survives a reload — the roster read, not just the stream, excludes them", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/provider/dashboard/team")
      view |> element("#end-employment-#{ctx.staff.id}") |> render_click()

      {:ok, reloaded, _html} = live(ctx.conn, ~p"/provider/dashboard/team")

      refute has_element?(reloaded, "#team_members-#{ctx.staff.id}")
      assert has_element?(reloaded, "#former_members-#{ctx.staff.id}")
    end

    test "keeps the employment row rather than destroying it", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/provider/dashboard/team")

      view |> element("#end-employment-#{ctx.staff.id}") |> render_click()

      assert {:ok, %{active: false}} = Provider.get_staff_member(ctx.staff.id)
    end

    test "reactivating puts them back on the roster", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/provider/dashboard/team")
      view |> element("#end-employment-#{ctx.staff.id}") |> render_click()

      view |> element("#reactivate-member-#{ctx.staff.id}") |> render_click()

      assert has_element?(view, "#team_members-#{ctx.staff.id}")
      refute has_element?(view, "#former_members-#{ctx.staff.id}")
      assert {:ok, %{active: true}} = Provider.get_staff_member(ctx.staff.id)
    end
  end

  describe "delete member" do
    test "offers deletion for a roster entry with no history", %{conn: conn, provider: provider} do
      typo = ProviderFixtures.staff_member_fixture(provider_id: provider.id, first_name: "Jhon")

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      assert has_element?(view, "#delete-member-#{typo.id}")

      view |> element("#delete-member-#{typo.id}") |> render_click()

      assert render(view) =~ "Team member removed."
      assert {:error, :not_found} = Provider.get_staff_member(typo.id)
    end

    test "does not offer deletion once the person has history", %{conn: conn, provider: provider} do
      # An invitation went out: a real person was told they work here, so the row
      # is no longer a typo to erase. Absent rather than disabled — the answer for
      # this member is End employment, and the UI should not suggest otherwise.
      invited =
        ProviderFixtures.staff_member_fixture(
          provider_id: provider.id,
          first_name: "Real",
          invitation_status: :sent
        )

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      assert has_element?(view, "#end-employment-#{invited.id}")
      refute has_element?(view, "#delete-member-#{invited.id}")
    end
  end

  describe "IDOR ownership guards" do
    setup %{provider: _provider} do
      # A second provider whose staff the logged-in provider must not touch.
      victim = ProviderFixtures.provider_profile_fixture()

      victim_staff =
        ProviderFixtures.staff_member_fixture(
          provider_id: victim.id,
          first_name: "Victim",
          last_name: "Member"
        )

      %{victim_staff: victim_staff}
    end

    test "edit_member on a foreign staff id is rejected and opens no form", %{
      conn: conn,
      victim_staff: victim_staff
    } do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      view = assert_idor_guarded(view, "edit_member", victim_staff.id, "Staff member not found.")

      refute has_element?(view, "#staff-member-form")
    end

    test "delete_member on a foreign staff id is rejected and leaves the row intact", %{
      conn: conn,
      victim_staff: victim_staff
    } do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      assert_idor_guarded(view, "delete_member", victim_staff.id, "Staff member not found.")

      assert {:ok, _still_there} = Provider.get_staff_member(victim_staff.id)
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
