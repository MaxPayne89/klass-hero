defmodule KlassHero.Accounts.UserNotifierStaffTest do
  use ExUnit.Case, async: true

  alias KlassHero.Accounts.UserNotifier

  describe "deliver_staff_invitation/3 (new user)" do
    test "invites to join the team with an accept link — no provider-account promise" do
      assert {:ok, email} =
               UserNotifier.deliver_staff_invitation(
                 "staff@example.com",
                 %{business_name: "Fun Academy", first_name: "Jane"},
                 "http://localhost:4000/users/staff-invitation/test-token"
               )

      assert email.to == [{"", "staff@example.com"}]
      assert email.subject == "Fun Academy has invited you to join their team on Klass Hero"
      assert email.text_body =~ "Jane"
      assert email.text_body =~ "Fun Academy"
      assert email.text_body =~ "test-token"
      assert email.text_body =~ "staff member"
      # ADR-0005: joining a team is not getting a provider account.
      refute email.text_body =~ "provider account"
    end
  end

  describe "deliver_staff_link_invitation/3 (existing user)" do
    test "tells an existing user to log in and accept — no registration, no provider account" do
      assert {:ok, email} =
               UserNotifier.deliver_staff_link_invitation(
                 "existing@example.com",
                 %{business_name: "Cool Sports", name: "Bob"},
                 "http://localhost:4000/users/staff-invitation/link-token"
               )

      assert email.to == [{"", "existing@example.com"}]
      assert email.subject == "Cool Sports has invited you to join their team on Klass Hero"
      assert email.text_body =~ "Bob"
      assert email.text_body =~ "Cool Sports"
      assert email.text_body =~ "link-token"
      assert email.text_body =~ "log in"
      refute email.text_body =~ "provider account"
    end
  end
end
