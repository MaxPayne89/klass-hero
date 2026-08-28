defmodule KlassHeroWeb.Staff.StaffBroadcastLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.AccountsFixtures
  import KlassHero.Factory, only: [insert: 2]
  import KlassHero.ProviderFixtures
  import Phoenix.LiveViewTest

  describe "staff broadcast (entitled)" do
    setup %{conn: conn} do
      parent_user = user_fixture(intended_roles: [:parent])
      provider = provider_profile_fixture()
      user = user_fixture(intended_roles: [:staff])

      staff =
        staff_member_fixture(%{
          provider_id: provider.id,
          user_id: user.id,
          active: true,
          invitation_status: :accepted,
          tags: ["sports"]
        })

      # Write model (programs table) for enrollment FK
      program =
        insert(:program_schema, provider_id: provider.id, category: "sports")

      # Read model (program_listings table) for dashboard/catalog queries

      # Compose is gated on this row since #1323, not on `tags` matching the category.
      program_assignment_fixture(%{
        provider_id: provider.id,
        program_id: program.id,
        staff_member_id: staff.id
      })

      parent_profile = insert(:parent_profile_schema, identity_id: parent_user.id)
      {child, _parent} = KlassHero.Factory.insert_child_with_guardian(parent: parent_profile)

      insert(:enrollment_schema,
        program_id: program.id,
        child_id: child.id,
        parent_id: parent_profile.id,
        status: "confirmed",
        confirmed_at: DateTime.utc_now()
      )

      conn = log_in_user(conn, user)

      %{conn: conn, user: user, provider: provider, staff: staff, program: program}
    end

    test "renders broadcast form for entitled staff member", %{conn: conn, program: program} do
      {:ok, view, _html} = live(conn, ~p"/staff/programs/#{program.id}/broadcast")

      assert has_element?(view, "#staff-broadcast-form")
      assert has_element?(view, "#send-broadcast-btn")
    end

    test "sends broadcast and navigates to staff messages", %{conn: conn, program: program} do
      {:ok, view, _html} = live(conn, ~p"/staff/programs/#{program.id}/broadcast")

      view
      |> form("#staff-broadcast-form", %{
        "subject" => "Test Subject",
        "content" => "Hello enrolled parents!"
      })
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path =~ "/staff/messages/"
    end

    @png_bytes <<137, 80, 78, 71, 13, 10, 26, 10>>

    test "renders the attachment uploader trigger", %{conn: conn, program: program} do
      {:ok, view, _html} = live(conn, ~p"/staff/programs/#{program.id}/broadcast")

      assert has_element?(view, "label", "Attach photo")
      assert has_element?(view, "input[type='file']")
    end

    test "sends broadcast with photo attachment and navigates to staff messages",
         %{conn: conn, program: program} do
      {:ok, view, _html} = live(conn, ~p"/staff/programs/#{program.id}/broadcast")

      photo =
        file_input(view, "#staff-broadcast-form", :attachments, [
          %{name: "team_photo.jpg", content: @png_bytes, type: "image/jpeg"}
        ])

      render_upload(photo, "team_photo.jpg")

      view
      |> form("#staff-broadcast-form", %{
        "subject" => "",
        "content" => "Look at the team!"
      })
      |> render_submit()

      {path, flash} = assert_redirect(view)
      assert path =~ "/staff/messages/"
      assert flash["info"] =~ "Broadcast sent"
    end

    # The issue's acceptance criteria never mentioned this surface. It closes with
    # no change here: composing is gated on `StaffProgramAccess.authorized?/2`,
    # which stopped saying yes once the program closed (#1082).
    test "rejects broadcast for a Closed Program the staff member is still assigned to",
         %{conn: conn, provider: provider, staff: staff} do
      closed =
        insert(:program_schema,
          provider_id: provider.id,
          category: "sports",
          end_date: Date.add(Date.utc_today(), -20)
        )

      program_assignment_fixture(%{
        provider_id: provider.id,
        program_id: closed.id,
        staff_member_id: staff.id
      })

      assert {:error, {:live_redirect, %{to: "/staff/dashboard"}}} =
               live(conn, ~p"/staff/programs/#{closed.id}/broadcast")
    end

    test "rejects broadcast for non-assigned program", %{conn: conn, provider: provider} do
      # Category "sports" matches the staff member's Specialties deliberately: what
      # rejects this is the missing Program Staff Assignment (#1323). Compose and the
      # reply guard in `Messaging.send_message` now scope the same way, so a staffer
      # can no longer open a compose page for a program their dashboard hides.
      unassigned_program =
        insert(:program_schema,
          provider_id: provider.id,
          category: "sports"
        )

      assert {:error, {:live_redirect, %{to: "/staff/dashboard", flash: flash}}} =
               live(conn, ~p"/staff/programs/#{unassigned_program.id}/broadcast")

      assert flash["error"] =~ "not assigned"
    end

    test "redirects to dashboard for any unreachable program (IDOR guard)", %{conn: conn} do
      foreign_provider = insert(:provider_profile_schema, %{})
      foreign_program = insert(:program_schema, provider_id: foreign_provider.id)

      unreachable = [
        {"foreign provider's program", foreign_program.id},
        {"nonexistent program", Ecto.UUID.generate()},
        {"malformed id", "not-a-uuid"}
      ]

      for {label, program_id} <- unreachable do
        assert {:error, {:live_redirect, %{to: "/staff/dashboard", flash: flash}}} =
                 live(conn, ~p"/staff/programs/#{program_id}/broadcast"),
               "expected #{label} to be rejected"

        assert flash["error"] == "Program not found", "wrong flash for #{label}"
      end
    end
  end

  describe "staff broadcast (former starter-tier provider)" do
    setup %{conn: conn} do
      provider = provider_profile_fixture()
      user = user_fixture(intended_roles: [:staff])

      staff =
        staff_member_fixture(%{
          provider_id: provider.id,
          user_id: user.id,
          active: true,
          invitation_status: :accepted,
          tags: ["sports"]
        })

      program =
        insert(:program_schema, provider_id: provider.id, category: "sports")

      program_assignment_fixture(%{
        provider_id: provider.id,
        program_id: program.id,
        staff_member_id: staff.id
      })

      conn = log_in_user(conn, user)
      %{conn: conn, program: program}
    end

    test "mounts broadcast compose for staff of former starter-tier provider", %{
      conn: conn,
      program: program
    } do
      # Provider tiers removed (ADR-0004): staff inherit messaging from any provider
      {:ok, view, _html} = live(conn, ~p"/staff/programs/#{program.id}/broadcast")

      assert has_element?(view, "#staff-broadcast-form")
    end
  end
end
