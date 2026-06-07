defmodule KlassHero.Accounts.UserNotifierStaffTest do
  use ExUnit.Case, async: true

  alias KlassHero.Accounts.UserNotifier

  describe "deliver_staff_invitation/3" do
    test "delivers unified invitation email with registration link" do
      assert {:ok, email} =
               UserNotifier.deliver_staff_invitation(
                 "staff@example.com",
                 %{business_name: "Fun Academy", first_name: "Jane"},
                 "http://localhost:4000/users/staff-invitation/test-token"
               )

      assert email.to == [{"", "staff@example.com"}]
      assert email.subject == "Fun Academy has invited you to join Klass Hero"
      assert email.text_body =~ "Jane"
      assert email.text_body =~ "Fun Academy"
      assert email.text_body =~ "test-token"
      assert email.text_body =~ "free provider account"
      assert email.text_body =~ "Claim your account"
      assert email.text_body =~ "terms of service"
    end
  end

  describe "deliver_staff_added_notification/2" do
    test "delivers unified notification email for existing users" do
      assert {:ok, email} =
               UserNotifier.deliver_staff_added_notification(
                 "existing@example.com",
                 %{
                   business_name: "Cool Sports",
                   name: "Bob",
                   dashboard_url: "http://localhost:4000/staff/dashboard"
                 }
               )

      assert email.to == [{"", "existing@example.com"}]
      assert email.subject == "Cool Sports has invited you to join Klass Hero"
      assert email.text_body =~ "Bob"
      assert email.text_body =~ "Cool Sports"
      assert email.text_body =~ "/staff/dashboard"
      assert email.text_body =~ "free provider account"
      assert email.text_body =~ "terms of service"
    end
  end
end
