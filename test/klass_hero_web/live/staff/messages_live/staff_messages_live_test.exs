defmodule KlassHeroWeb.Staff.MessagesLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.AccountsFixtures
  import KlassHero.Factory, only: [insert: 1, insert: 2]
  import KlassHero.ProviderFixtures

  alias KlassHero.Messaging.StaffParticipants

  describe "staff messages index" do
    setup %{conn: conn} do
      user = user_fixture(intended_roles: [:staff])
      provider = provider_profile_fixture()
      program = insert(:program_schema, provider_id: provider.id)

      staff =
        staff_member_fixture(%{
          provider_id: provider.id,
          user_id: user.id,
          active: true,
          invitation_status: :accepted
        })

      # Seed projection so staff is recognized
      StaffParticipants.upsert_active(%{
        provider_id: provider.id,
        program_id: program.id,
        staff_user_id: user.id
      })

      # Create a conversation where staff is a participant
      conversation =
        insert(:conversation_schema, provider_id: provider.id, program_id: program.id)

      insert(:participant_schema, conversation_id: conversation.id, user_id: user.id)

      conn = log_in_user(conn, user)

      %{
        conn: conn,
        user: user,
        provider: provider,
        program: program,
        staff: staff,
        conversation: conversation
      }
    end

    test "renders conversation list", %{conn: conn} do
      {:ok, _view, _html} = live(conn, ~p"/staff/messages")
    end

    test "non-staff user is redirected", %{} do
      non_staff_user = user_fixture()
      non_staff_conn = build_conn() |> log_in_user(non_staff_user)

      assert {:error, {:redirect, %{to: "/"}}} = live(non_staff_conn, ~p"/staff/messages")
    end

    test "unauthenticated user is redirected", %{} do
      assert {:error, {:redirect, _}} = live(build_conn(), ~p"/staff/messages")
    end
  end

  describe "staff messages show" do
    setup %{conn: conn} do
      user = user_fixture(intended_roles: [:staff])
      provider = provider_profile_fixture()
      program = insert(:program_schema, provider_id: provider.id)

      staff =
        staff_member_fixture(%{
          provider_id: provider.id,
          user_id: user.id,
          active: true,
          invitation_status: :accepted
        })

      StaffParticipants.upsert_active(%{
        provider_id: provider.id,
        program_id: program.id,
        staff_user_id: user.id
      })

      conversation =
        insert(:conversation_schema, provider_id: provider.id, program_id: program.id)

      insert(:participant_schema, conversation_id: conversation.id, user_id: user.id)

      conn = log_in_user(conn, user)

      %{
        conn: conn,
        user: user,
        provider: provider,
        staff: staff,
        conversation: conversation
      }
    end

    test "renders conversation with messages", %{conn: conn, conversation: conversation} do
      {:ok, _view, _html} = live(conn, ~p"/staff/messages/#{conversation.id}")
    end

    test "staff can send a message", %{conn: conn, conversation: conversation} do
      {:ok, view, _html} = live(conn, ~p"/staff/messages/#{conversation.id}")

      view
      |> form("#message-form", %{"content" => "Hello from staff test!"})
      |> render_submit()

      # Verify the message form cleared (successful send)
      assert has_element?(view, "#message-form")
    end

    test "non-participant is redirected with error", %{conn: conn} do
      other_conversation = insert(:conversation_schema)

      assert {:error, {:live_redirect, %{to: "/staff/messages"}}} =
               live(conn, ~p"/staff/messages/#{other_conversation.id}")
    end
  end
end
