defmodule KlassHero.Accounts.EmailNotificationGateTest do
  @moduledoc """
  The contract every context asks before emailing someone.

  Accounts owns the vocabulary and the answer; a producing context asks and
  never touches the column. The stored list is what is *disabled*, and this is
  the only module allowed to know that — callers speak in "enabled?".
  """
  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures

  alias KlassHero.Accounts

  @kind :new_message_email

  describe "email_notification_enabled?/2" do
    test "defaults to on for a user who has never touched the setting" do
      user = user_fixture()

      assert user.disabled_email_notifications == []
      assert Accounts.email_notification_enabled?(user, @kind)
    end

    test "is off once the user opts out" do
      user = user_fixture()
      {:ok, user} = Accounts.update_user_email_notification_preference(user, @kind, false)

      refute Accounts.email_notification_enabled?(user, @kind)
    end
  end

  describe "update_user_email_notification_preference/3" do
    test "opting out then back in returns to the enabled state" do
      user = user_fixture()

      {:ok, disabled} = Accounts.update_user_email_notification_preference(user, @kind, false)
      # Pin the intermediate state: without this, the final assertion below
      # would pass even if neither call did anything.
      assert disabled.disabled_email_notifications == [@kind]

      {:ok, enabled} = Accounts.update_user_email_notification_preference(disabled, @kind, true)
      assert enabled.disabled_email_notifications == []
    end

    test "opting out twice does not duplicate the entry" do
      user = user_fixture()

      {:ok, once} = Accounts.update_user_email_notification_preference(user, @kind, false)
      {:ok, twice} = Accounts.update_user_email_notification_preference(once, @kind, false)

      assert twice.disabled_email_notifications == [@kind]
    end

    # The column holds every kind at once, so a list computed from a struct that
    # predates someone else's write silently re-enables whatever changed since.
    # One kind cannot show that directly — both branches produce the same list —
    # so this probes the reload itself, through a field the caller staled.
    test "computes the next list from the stored row, not the caller's struct" do
      user = user_fixture()
      {:ok, _} = Accounts.update_user_email_notification_preference(user, @kind, false)

      stale = %{user | name: "only in this struct"}

      {:ok, updated} = Accounts.update_user_email_notification_preference(stale, @kind, false)

      assert updated.disabled_email_notifications == [@kind]

      refute updated.name == "only in this struct",
             "the write was computed from the caller's struct rather than the stored row"
    end

    test "opting in when already enabled is a no-op" do
      user = user_fixture()

      {:ok, updated} = Accounts.update_user_email_notification_preference(user, @kind, true)

      assert updated.disabled_email_notifications == []
    end
  end

  describe "notifiable_recipients/2" do
    test "returns address and name for users who want the notification" do
      user = user_fixture()

      recipients = Accounts.notifiable_recipients([user.id], @kind)

      assert %{email: email, name: name} = Map.fetch!(recipients, user.id)
      assert email == user.email
      assert name == user.name
    end

    test "omits users who opted out" do
      wants = user_fixture()
      declines = user_fixture()
      {:ok, declines} = Accounts.update_user_email_notification_preference(declines, @kind, false)

      recipients = Accounts.notifiable_recipients([wants.id, declines.id], @kind)

      assert Map.has_key?(recipients, wants.id)
      refute Map.has_key?(recipients, declines.id)
    end

    test "omits ids that match no user instead of raising" do
      user = user_fixture()

      recipients = Accounts.notifiable_recipients([user.id, Ecto.UUID.generate()], @kind)

      assert Map.keys(recipients) == [user.id]
    end

    test "short-circuits on an empty list" do
      assert Accounts.notifiable_recipients([], @kind) == %{}
    end
  end
end
