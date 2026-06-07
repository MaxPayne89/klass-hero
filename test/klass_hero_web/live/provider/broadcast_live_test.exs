defmodule KlassHeroWeb.Provider.BroadcastLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.Factory
  import Phoenix.LiveViewTest

  alias KlassHero.AccountsFixtures

  describe "authentication and authorization" do
    test "requires authentication", %{conn: conn} do
      program = insert(:program_schema)

      assert {:error, redirect} = live(conn, ~p"/provider/programs/#{program.id}/broadcast")
      assert {:redirect, %{to: path}} = redirect
      assert path =~ "/users/log-in"
    end

    test "requires provider role", %{conn: conn} do
      program = insert(:program_schema)
      %{conn: conn} = register_and_log_in_user(%{conn: conn})

      assert {:error, redirect} = live(conn, ~p"/provider/programs/#{program.id}/broadcast")
      assert {:redirect, %{to: path}} = redirect
      assert path == "/"
    end
  end

  describe "program validation" do
    setup :register_and_log_in_provider

    test "redirects when program not found", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/provider/dashboard/programs", flash: flash}}} =
               live(conn, ~p"/provider/programs/#{Ecto.UUID.generate()}/broadcast")

      assert flash["error"] == "Program not found"
    end
  end

  describe "broadcast form" do
    setup :register_and_log_in_provider

    test "renders broadcast form for valid program", %{conn: conn} do
      program = insert(:program_schema)

      {:ok, view, _html} = live(conn, ~p"/provider/programs/#{program.id}/broadcast")

      assert has_element?(view, "h1", "Send Broadcast")
      assert has_element?(view, "#broadcast-form")
      assert has_element?(view, "input[name=\"subject\"]")
      assert has_element?(view, "textarea[name=\"content\"]")
    end

    test "shows program title", %{conn: conn} do
      program = insert(:program_schema, title: "Junior Soccer Academy")

      {:ok, view, _html} = live(conn, ~p"/provider/programs/#{program.id}/broadcast")

      assert has_element?(view, "p", "Junior Soccer Academy")
    end

    test "shows warning about broadcast reach", %{conn: conn} do
      program = insert(:program_schema)

      {:ok, view, _html} = live(conn, ~p"/provider/programs/#{program.id}/broadcast")

      assert has_element?(view, "p", ~r/sent to all parents with active enrollments/)
    end
  end

  describe "sending broadcast" do
    setup :register_and_log_in_provider

    test "shows error when content is empty", %{conn: conn} do
      program = insert(:program_schema)

      {:ok, view, _html} = live(conn, ~p"/provider/programs/#{program.id}/broadcast")

      view
      |> form("#broadcast-form", %{"subject" => "Test", "content" => ""})
      |> render_submit()

      assert_flash(view, :error, "Message content is required")
    end

    test "shows error when content is only whitespace", %{conn: conn} do
      program = insert(:program_schema)

      {:ok, view, _html} = live(conn, ~p"/provider/programs/#{program.id}/broadcast")

      view
      |> form("#broadcast-form", %{"subject" => "Test", "content" => "   "})
      |> render_submit()

      assert_flash(view, :error, "Message content is required")
    end

    test "shows no_enrollments error when no parents enrolled", %{conn: conn} do
      program = insert(:program_schema)

      {:ok, view, _html} = live(conn, ~p"/provider/programs/#{program.id}/broadcast")

      view
      |> form("#broadcast-form", %{"subject" => "Update", "content" => "Hello everyone!"})
      |> render_submit()

      assert_flash(view, :error, "No parents are enrolled in this program")
    end

    test "mounts broadcast compose for former starter-tier provider", %{conn: conn} do
      # Provider tiers removed (ADR-0004): every provider can broadcast
      user = AccountsFixtures.user_fixture(%{intended_roles: [:provider]})

      _provider =
        insert(:provider_profile_schema, identity_id: user.id)

      conn = log_in_user(conn, user)
      program = insert(:program_schema)
      parent = insert(:parent_profile_schema)

      insert(:enrollment_schema,
        program_id: program.id,
        parent_id: parent.id,
        status: "confirmed"
      )

      {:ok, view, _html} = live(conn, ~p"/provider/programs/#{program.id}/broadcast")

      assert has_element?(view, "#broadcast-form")
    end

    test "successfully sends broadcast to enrolled parents", %{conn: conn} do
      program = insert(:program_schema)
      parent_user = AccountsFixtures.user_fixture()
      parent = insert(:parent_profile_schema, identity_id: parent_user.id)

      insert(:enrollment_schema,
        program_id: program.id,
        parent_id: parent.id,
        status: "confirmed"
      )

      {:ok, view, _html} = live(conn, ~p"/provider/programs/#{program.id}/broadcast")

      view
      |> form("#broadcast-form", %{
        "subject" => "Schedule Change",
        "content" => "Important update about class times."
      })
      |> render_submit()

      # After success, the view navigates to the conversation page
      # Check the redirect path and flash
      {path, flash} = assert_redirect(view)
      assert path =~ "/provider/messages/"
      assert flash["info"] =~ "Broadcast sent"
    end

    test "sends broadcast without subject", %{conn: conn} do
      program = insert(:program_schema)
      parent_user = AccountsFixtures.user_fixture()
      parent = insert(:parent_profile_schema, identity_id: parent_user.id)

      insert(:enrollment_schema,
        program_id: program.id,
        parent_id: parent.id,
        status: "confirmed"
      )

      {:ok, view, _html} = live(conn, ~p"/provider/programs/#{program.id}/broadcast")

      view
      |> form("#broadcast-form", %{
        "subject" => "",
        "content" => "Hello everyone!"
      })
      |> render_submit()

      # After success, the view navigates to the conversation page
      {path, flash} = assert_redirect(view)
      assert path =~ "/provider/messages/"
      assert flash["info"] =~ "Broadcast sent"
    end
  end

  describe "broadcast with attachments" do
    setup :register_and_log_in_provider

    @png_bytes <<137, 80, 78, 71, 13, 10, 26, 10>>

    test "renders the attachment uploader trigger", %{conn: conn} do
      program = insert(:program_schema)

      {:ok, view, _html} = live(conn, ~p"/provider/programs/#{program.id}/broadcast")

      assert has_element?(view, "label", "Attach photo")
      assert has_element?(view, "input[type='file']")
    end

    test "sends broadcast with photo attachment and navigates to conversation", %{conn: conn} do
      program = insert(:program_schema)
      parent_user = AccountsFixtures.user_fixture()
      parent = insert(:parent_profile_schema, identity_id: parent_user.id)

      insert(:enrollment_schema,
        program_id: program.id,
        parent_id: parent.id,
        status: "confirmed"
      )

      {:ok, view, _html} = live(conn, ~p"/provider/programs/#{program.id}/broadcast")

      photo =
        file_input(view, "#broadcast-form", :attachments, [
          %{name: "announcement.jpg", content: @png_bytes, type: "image/jpeg"}
        ])

      render_upload(photo, "announcement.jpg")

      view
      |> form("#broadcast-form", %{
        "subject" => "",
        "content" => "Check this out"
      })
      |> render_submit()

      {path, flash} = assert_redirect(view)
      assert path =~ "/provider/messages/"
      assert flash["info"] =~ "Broadcast sent"
    end
  end

  describe "cancel navigation" do
    setup :register_and_log_in_provider

    test "cancel link navigates back to programs", %{conn: conn} do
      program = insert(:program_schema)

      {:ok, view, _html} = live(conn, ~p"/provider/programs/#{program.id}/broadcast")

      html = render(view)
      assert html =~ "/provider/dashboard/programs"
      assert has_element?(view, "a", "Cancel")
    end
  end

  describe "sidebar navigation" do
    setup :register_and_log_in_provider

    test "highlights Comms in the sidebar", %{conn: conn} do
      program = insert(:program_schema)

      {:ok, view, _html} = live(conn, ~p"/provider/programs/#{program.id}/broadcast")

      assert has_element?(view, "a[aria-current='page']", "Comms")
    end
  end
end
