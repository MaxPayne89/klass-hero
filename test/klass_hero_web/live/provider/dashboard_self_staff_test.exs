defmodule KlassHeroWeb.Provider.DashboardSelfStaffTest do
  @moduledoc """
  Self-staffing flow (#969) on the provider dashboard team tab.

  Deliberately does NOT use the module-level `register_and_log_in_provider`
  setup from the team test file — these tests need a provider with a KNOWN
  account name for pre-fill assertions, and a second fixture chain per test
  would be discarded waste.
  """

  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.AccountsFixtures
  import KlassHero.EmailTestHelper
  import KlassHero.ProviderFixtures
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias KlassHero.Accounts.User
  alias KlassHero.Provider

  defp log_in_named_provider(conn, name) do
    user = user_fixture(%{intended_roles: [:provider], name: name})
    provider = KlassHero.Factory.insert(:provider_profile_schema, identity_id: user.id)
    %{conn: log_in_user(conn, user), user: user, provider: provider}
  end

  # Founder who has already been granted :staff (self-staffed): the durable
  # teardown is only observable when :staff actually sits in intended_roles.
  defp log_in_provider_also_staff(conn) do
    user = user_fixture(%{intended_roles: [:provider, :staff], name: "Maxi Founder"})
    provider = KlassHero.Factory.insert(:provider_profile_schema, identity_id: user.id)
    %{conn: log_in_user(conn, user), user: user, provider: provider}
  end

  defp reload_roles(user_id), do: KlassHero.Repo.get!(User, user_id).intended_roles

  describe "button visibility" do
    test "provider sees the self-staff button; an already self-staffed provider does not", %{
      conn: conn
    } do
      %{conn: conn, user: user, provider: provider} = log_in_named_provider(conn, "Maxi Founder")

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")
      assert has_element?(view, "#self-staff-btn")

      staff_member_fixture(
        provider_id: provider.id,
        user_id: user.id,
        invitation_status: :accepted,
        active: true
      )

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")
      refute has_element?(view, "#self-staff-btn")
    end
  end

  describe "pre-filled form" do
    test "clicking the button opens the form pre-filled, with the email readonly", %{conn: conn} do
      %{conn: conn, user: user} = log_in_named_provider(conn, "Maxi Founder")

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")
      view |> element("#self-staff-btn") |> render_click()

      assert has_element?(view, "#staff-member-form")
      assert has_element?(view, "input[name='staff_member_schema[first_name]'][value='Maxi']")
      assert has_element?(view, "input[name='staff_member_schema[last_name]'][value='Founder']")

      # The linked self row always carries the account email — field is locked.
      assert has_element?(
               view,
               "input[name='staff_member_schema[email]'][value='#{user.email}'][readonly]"
             )
    end
  end

  describe "submit" do
    test "creates a linked accepted row, grants :staff, sends no email", %{conn: conn} do
      %{conn: conn, user: user, provider: provider} = log_in_named_provider(conn, "Maxi Founder")

      # Drain registration/confirmation emails from the fixture so the final
      # no-email assertion targets only the self-staffing action.
      flush_emails()

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")
      refute has_element?(view, "#cross-nav-staff-link")

      view |> element("#self-staff-btn") |> render_click()

      view
      |> form("#staff-form", %{
        "staff_member_schema" => %{
          "first_name" => "Maxi",
          "last_name" => "Founder",
          "role" => "Head Coach"
        }
      })
      |> render_submit()

      html = render(view)
      assert html =~ "Maxi Founder"
      assert has_element?(view, "#cross-nav-staff-link")
      refute has_element?(view, "#self-staff-btn")

      {:ok, [staff]} = Provider.list_staff_members(provider.id)
      assert staff.user_id == user.id
      assert staff.invitation_status == :accepted
      assert is_nil(staff.invitation_token_hash)
      assert staff.email == user.email

      reloaded = KlassHero.Repo.get!(User, user.id)
      assert :staff in reloaded.intended_roles

      assert_no_email_sent()
    end

    test "single-word account name leaves last name empty; submit fails validation", %{
      conn: conn
    } do
      %{conn: conn, provider: provider} = log_in_named_provider(conn, "Cher")

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")
      view |> element("#self-staff-btn") |> render_click()

      assert has_element?(view, "input[name='staff_member_schema[last_name]'][value='']")

      html =
        view
        |> form("#staff-form", %{
          "staff_member_schema" => %{"first_name" => "Cher", "last_name" => ""}
        })
        |> render_submit()

      assert html =~ "can&#39;t be blank"
      assert {:ok, []} = Provider.list_staff_members(provider.id)
    end

    test "stale tab: submitting after self-staffing elsewhere converges the whole page", %{
      conn: conn
    } do
      %{conn: conn, user: user, provider: provider} = log_in_named_provider(conn, "Maxi Founder")

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")
      view |> element("#self-staff-btn") |> render_click()

      # The self row appears from another tab while the form is open.
      staff_member_fixture(
        provider_id: provider.id,
        user_id: user.id,
        first_name: "Maxi",
        last_name: "Founder",
        invitation_status: :accepted,
        active: true
      )

      view
      |> form("#staff-form", %{
        "staff_member_schema" => %{"first_name" => "Maxi", "last_name" => "Founder"}
      })
      |> render_submit()

      # Full convergence: flags, roster, and cross-nav — not just the flash.
      refute has_element?(view, "#staff-member-form")
      refute has_element?(view, "#self-staff-btn")
      assert has_element?(view, "#cross-nav-staff-link")
      assert render(view) =~ "Maxi Founder"

      assert {:ok, [_only_one]} = Provider.list_staff_members(provider.id)
    end
  end

  describe "deleting the own self row" do
    test "heals the page: button returns, cross-nav goes (single employer)", %{conn: conn} do
      %{conn: conn, user: user, provider: provider} = log_in_named_provider(conn, "Maxi Founder")

      staff =
        staff_member_fixture(
          provider_id: provider.id,
          user_id: user.id,
          invitation_status: :accepted,
          active: true
        )

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")
      refute has_element?(view, "#self-staff-btn")

      view
      |> element(~s(button[phx-click="delete_member"][phx-value-id="#{staff.id}"]))
      |> render_click()

      assert has_element?(view, "#self-staff-btn")
      refute has_element?(view, "#cross-nav-staff-link")
    end

    test "keeps the cross-nav when still staff at another employer", %{conn: conn} do
      %{conn: conn, user: user, provider: provider} = log_in_named_provider(conn, "Maxi Founder")

      employer = provider_profile_fixture()

      staff_member_fixture(
        provider_id: employer.id,
        user_id: user.id,
        invitation_status: :accepted,
        active: true
      )

      own_row =
        staff_member_fixture(
          provider_id: provider.id,
          user_id: user.id,
          invitation_status: :accepted,
          active: true
        )

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      view
      |> element(~s(button[phx-click="delete_member"][phx-value-id="#{own_row.id}"]))
      |> render_click()

      assert has_element?(view, "#self-staff-btn")
      assert has_element?(view, "#cross-nav-staff-link")
    end
  end

  describe "durable :staff teardown (#972)" do
    test "deleting the last linked row removes :staff from intended_roles", %{conn: conn} do
      %{conn: conn, user: user, provider: provider} = log_in_provider_also_staff(conn)

      staff =
        staff_member_fixture(
          provider_id: provider.id,
          user_id: user.id,
          invitation_status: :accepted,
          active: true
        )

      assert :staff in reload_roles(user.id)

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      view
      |> element(~s(button[phx-click="delete_member"][phx-value-id="#{staff.id}"]))
      |> render_click()

      # Durable: survives a fresh DB read, not just the in-session heal.
      assert reload_roles(user.id) == [:provider]
    end

    test "deleting one of several linked rows keeps :staff", %{conn: conn} do
      %{conn: conn, user: user, provider: provider} = log_in_provider_also_staff(conn)

      employer = provider_profile_fixture()

      staff_member_fixture(
        provider_id: employer.id,
        user_id: user.id,
        invitation_status: :accepted,
        active: true
      )

      own_row =
        staff_member_fixture(
          provider_id: provider.id,
          user_id: user.id,
          invitation_status: :accepted,
          active: true
        )

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      view
      |> element(~s(button[phx-click="delete_member"][phx-value-id="#{own_row.id}"]))
      |> render_click()

      assert :staff in reload_roles(user.id)
    end
  end
end
