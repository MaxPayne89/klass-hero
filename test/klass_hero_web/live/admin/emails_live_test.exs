defmodule KlassHeroWeb.Admin.EmailsLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias KlassHero.MessagingFixtures

  setup :register_and_log_in_admin

  describe "Index" do
    test "lists inbound emails", %{conn: conn} do
      email = MessagingFixtures.inbound_email_fixture(%{subject: "Hello Admin"})
      {:ok, view, _html} = live(conn, ~p"/admin/emails")
      assert has_element?(view, "#emails-table")
      assert render(view) =~ "Hello Admin"
      assert render(view) =~ email.from_address
    end

    test "filters by status", %{conn: conn} do
      MessagingFixtures.inbound_email_fixture(%{status: "unread", subject: "Unread One"})
      MessagingFixtures.inbound_email_fixture(%{status: "read", subject: "Read One"})

      {:ok, view, _html} = live(conn, ~p"/admin/emails")
      assert render(view) =~ "Unread One"
      assert render(view) =~ "Read One"

      view |> element("#filter-unread") |> render_click()
      assert render(view) =~ "Unread One"
      refute render(view) =~ "Read One"
    end

    test "shows empty state when no emails", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/emails")
      assert has_element?(view, "#emails-empty")
    end

    # @current_url comes from Backpex.InitAssigns' handle_params hook, attached in
    # the :admin_custom live_session. Nothing else asserts that hook is wired, so
    # dropping it from the router would otherwise surface as a runtime KeyError.
    test "highlights the Emails sidebar item", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/emails")

      assert has_element?(view, ~s|a[href="/admin/emails"].bg-neutral|)
      refute has_element?(view, ~s|a[href="/admin/sessions"].bg-neutral|)
    end
  end

  describe "Show" do
    test "displays email detail with sanitized HTML", %{conn: conn} do
      email =
        MessagingFixtures.inbound_email_fixture(%{
          subject: "Important Message",
          body_html: "<p>Hello <strong>world</strong></p><script>evil()</script>"
        })

      {:ok, _view, html} = live(conn, ~p"/admin/emails/#{email.id}")
      assert html =~ "Important Message"
      assert html =~ "<strong>world</strong>"
      refute html =~ "<script>"
    end

    test "shows reply form", %{conn: conn} do
      email = MessagingFixtures.inbound_email_fixture()
      {:ok, view, _html} = live(conn, ~p"/admin/emails/#{email.id}")
      assert has_element?(view, "#reply-form")
    end

    test "navigates back to index", %{conn: conn} do
      email = MessagingFixtures.inbound_email_fixture()
      {:ok, view, _html} = live(conn, ~p"/admin/emails/#{email.id}")
      assert has_element?(view, "#back-to-emails")
    end

    test "redirects on invalid id", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/admin/emails"}}} =
               live(conn, ~p"/admin/emails/not-a-uuid")
    end

    test "submitting a reply shows success flash", %{conn: conn} do
      email = MessagingFixtures.inbound_email_fixture(%{subject: "Reply Test"})
      {:ok, view, _html} = live(conn, ~p"/admin/emails/#{email.id}")

      view
      |> form("#reply-form", reply: %{body: "Thanks for your email!"})
      |> render_submit()

      assert render(view) =~ "Reply sent successfully"
    end

    test "archiving an email shows success flash", %{conn: conn} do
      email = MessagingFixtures.inbound_email_fixture(%{status: "read", subject: "Archive Test"})
      {:ok, view, _html} = live(conn, ~p"/admin/emails/#{email.id}")

      assert has_element?(view, "#archive-btn")

      view |> element("#archive-btn") |> render_click()

      assert render(view) =~ "Email archived"
    end
  end

  describe "Show - content status" do
    test "shows loading placeholder for pending content", %{conn: conn} do
      email =
        MessagingFixtures.inbound_email_fixture(%{
          content_status: "pending",
          body_html: nil,
          body_text: nil
        })

      {:ok, view, _html} = live(conn, ~p"/admin/emails/#{email.id}")
      assert render(view) =~ "Content is being fetched"
    end

    test "shows error for failed content fetch", %{conn: conn} do
      email =
        MessagingFixtures.inbound_email_fixture(%{
          content_status: "failed",
          body_html: nil,
          body_text: nil
        })

      {:ok, view, _html} = live(conn, ~p"/admin/emails/#{email.id}")
      assert render(view) =~ "Failed to fetch"
      assert has_element?(view, "#retry-fetch-btn")
    end
  end

  describe "Show - replies" do
    test "displays sent replies", %{conn: conn} do
      email = MessagingFixtures.inbound_email_fixture()

      MessagingFixtures.email_reply_fixture(%{
        inbound_email_id: email.id,
        body: "We got your message!"
      })

      {:ok, view, _html} = live(conn, ~p"/admin/emails/#{email.id}")
      assert render(view) =~ "We got your message!"
    end

    test "shows reply list container", %{conn: conn} do
      email = MessagingFixtures.inbound_email_fixture()
      MessagingFixtures.email_reply_fixture(%{inbound_email_id: email.id})

      {:ok, view, _html} = live(conn, ~p"/admin/emails/#{email.id}")
      assert has_element?(view, "#replies-list")
    end
  end
end
