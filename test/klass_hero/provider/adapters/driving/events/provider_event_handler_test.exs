defmodule KlassHero.Provider.Adapters.Driving.Events.ProviderEventHandlerTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.AccountsFixtures
  alias KlassHero.Provider
  alias KlassHero.Provider.Adapters.Driving.Events.ProviderEventHandler

  describe "handle_event/1 for :user_registered" do
    test "creates provider profile when 'provider' in intended_roles" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])

      event = build_user_registered_event(user)
      assert :ok = ProviderEventHandler.handle_event(event)

      assert {:ok, _profile} = Provider.get_provider_by_identity(user.id)
    end

    test "ignores event when 'provider' not in intended_roles" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:parent])

      event = build_user_registered_event(user, intended_roles: ["parent"])
      assert :ignore = ProviderEventHandler.handle_event(event)
    end

    test "captures business_owner_email from payload" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])

      event = build_user_registered_event(user, email: "owner@example.com")
      assert :ok = ProviderEventHandler.handle_event(event)

      assert {:ok, profile} = Provider.get_provider_by_identity(user.id)
      assert profile.business_owner_email == "owner@example.com"
    end

    test "leaves business_owner_email nil when payload omits :email" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])

      event = build_user_registered_event(user)
      payload = Map.delete(event.payload, :email)
      assert :ok = ProviderEventHandler.handle_event(%{event | payload: payload})

      assert {:ok, profile} = Provider.get_provider_by_identity(user.id)
      assert profile.business_owner_email == nil
    end
  end

  describe "handle_event/1 for :user_anonymized" do
    test "returns :ok (no-op)" do
      event = %{event_type: :user_anonymized, entity_id: Ecto.UUID.generate()}
      assert :ok = ProviderEventHandler.handle_event(event)
    end
  end

  describe "handle_event/1 for unknown events" do
    test "returns :ignore" do
      event = %{event_type: :unknown_event, entity_id: Ecto.UUID.generate()}
      assert :ignore = ProviderEventHandler.handle_event(event)
    end
  end

  describe "handle_event/1 for :user_confirmed" do
    test "creates provider profile when 'provider' in intended_roles" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])

      event = build_user_confirmed_event(user)
      assert :ok = ProviderEventHandler.handle_event(event)

      assert {:ok, _profile} = Provider.get_provider_by_identity(user.id)
    end

    test "returns :ok when provider profile already exists (idempotent)" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])

      # First call creates the profile
      registered_event = build_user_registered_event(user)
      assert :ok = ProviderEventHandler.handle_event(registered_event)

      # Second call via user_confirmed is idempotent
      confirmed_event = build_user_confirmed_event(user)
      assert :ok = ProviderEventHandler.handle_event(confirmed_event)

      # Only one profile exists
      assert {:ok, _profile} = Provider.get_provider_by_identity(user.id)
    end

    test "ignores event when 'provider' not in intended_roles" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:parent])

      event = build_user_confirmed_event(user, intended_roles: ["parent"])
      assert :ignore = ProviderEventHandler.handle_event(event)
    end

    test "captures business_owner_email from payload" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])

      event = build_user_confirmed_event(user, email: "confirmed@example.com")
      assert :ok = ProviderEventHandler.handle_event(event)

      assert {:ok, profile} = Provider.get_provider_by_identity(user.id)
      assert profile.business_owner_email == "confirmed@example.com"
    end
  end

  describe "subscribed_events/0" do
    test "includes :user_confirmed" do
      assert :user_confirmed in ProviderEventHandler.subscribed_events()
    end
  end

  # Helpers

  defp build_user_registered_event(user, opts \\ []) do
    intended_roles = Keyword.get(opts, :intended_roles, ["provider"])
    email = Keyword.get(opts, :email, user.email)

    %{
      event_type: :user_registered,
      entity_id: user.id,
      payload: %{
        intended_roles: intended_roles,
        name: user.name || "Test Provider",
        email: email
      }
    }
  end

  defp build_user_confirmed_event(user, opts \\ []) do
    intended_roles = Keyword.get(opts, :intended_roles, ["provider"])
    email = Keyword.get(opts, :email, user.email)

    %{
      event_type: :user_confirmed,
      entity_id: user.id,
      payload: %{
        intended_roles: intended_roles,
        name: user.name || "Test Provider",
        email: email
      }
    }
  end
end
