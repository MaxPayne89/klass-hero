defmodule KlassHero.Accounts.UserEmailNotificationPreferencesTest do
  @moduledoc """
  The changeset that decides which email notifications a user has switched off.

  The column stores what is *disabled*, so absence means enabled. That inversion
  is why `[]` must stay valid — it is the state every user starts in — while
  `nil` must not, because the column is `null: false` and a nil would only ever
  reach it through a bug.
  """
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias KlassHero.Accounts.User

  describe "email_notification_preferences_changeset/2" do
    test "accepts every kind the app claims to support" do
      # Without this the loop below is vacuous: an empty vocabulary would pass
      # every assertion in this file by never running one.
      refute Enum.empty?(User.email_notification_kinds()),
             "email_notification_kinds/0 is empty — every test here would be vacuous"

      for kind <- User.email_notification_kinds() do
        changeset =
          User.email_notification_preferences_changeset(%User{}, %{
            disabled_email_notifications: [kind]
          })

        assert changeset.valid?,
               "#{kind} is in email_notification_kinds/0 but the changeset rejects it: " <>
                 inspect(changeset.errors)

        assert Changeset.get_field(changeset, :disabled_email_notifications) == [kind]
      end
    end

    # Deliberately not plausible-looking kinds: adding one of these for real
    # would make the fixture wrong rather than making the test fail loudly.
    @never_kinds [:new_message_sms, :marketing_digest, :not_a_kind]

    test "rejects anything outside that set" do
      assert Enum.all?(@never_kinds, &(&1 not in User.email_notification_kinds())),
             "fixture overlaps email_notification_kinds/0 — this test would be vacuous"

      for kind <- @never_kinds do
        changeset =
          User.email_notification_preferences_changeset(%User{}, %{
            disabled_email_notifications: [kind]
          })

        refute changeset.valid?, "#{inspect(kind)} was accepted as a notification kind"
        assert Keyword.has_key?(changeset.errors, :disabled_email_notifications)
      end
    end

    test "accepts the empty list — that is the everything-enabled state" do
      changeset =
        User.email_notification_preferences_changeset(%User{}, %{
          disabled_email_notifications: []
        })

      assert changeset.valid?
      assert Changeset.get_field(changeset, :disabled_email_notifications) == []
    end

    test "rejects nil rather than writing it to a null: false column" do
      changeset =
        User.email_notification_preferences_changeset(
          %User{disabled_email_notifications: [:new_message_email]},
          %{disabled_email_notifications: nil}
        )

      refute changeset.valid?
      assert {"can't be blank", _meta} = changeset.errors[:disabled_email_notifications]
    end

    test "casts nothing but the preference field" do
      changeset =
        User.email_notification_preferences_changeset(%User{}, %{
          disabled_email_notifications: [],
          email: "attacker@example.com",
          is_admin: true
        })

      assert changeset.changes == %{}
    end
  end
end
