defmodule KlassHero.Accounts.Domain.Events.UserEventsTest do
  use ExUnit.Case, async: true

  alias KlassHero.Accounts.Domain.Events.UserEvents

  describe "user_registered/3 validation" do
    test "raises when user.id is nil" do
      user = %{id: nil, email: "test@example.com", name: "Test User"}

      assert_raise ArgumentError,
                   "User.id cannot be nil for user_registered event",
                   fn -> UserEvents.user_registered(user) end
    end

    test "raises when user.email is nil" do
      user = %{id: 1, email: nil, name: "Test User"}

      assert_raise ArgumentError,
                   "User.email cannot be nil or empty for user_registered event",
                   fn -> UserEvents.user_registered(user) end
    end

    test "raises when user.email is empty string" do
      user = %{id: 1, email: "", name: "Test User"}

      assert_raise ArgumentError,
                   "User.email cannot be nil or empty for user_registered event",
                   fn -> UserEvents.user_registered(user) end
    end

    test "raises when user.name is nil" do
      user = %{id: 1, email: "test@example.com", name: nil}

      assert_raise ArgumentError,
                   "User.name cannot be nil or empty for user_registered event",
                   fn -> UserEvents.user_registered(user) end
    end

    test "raises when user.name is empty string" do
      user = %{id: 1, email: "test@example.com", name: ""}

      assert_raise ArgumentError,
                   "User.name cannot be nil or empty for user_registered event",
                   fn -> UserEvents.user_registered(user) end
    end

    test "succeeds with valid user" do
      user = %{id: 1, email: "test@example.com", name: "Test User"}

      event = UserEvents.user_registered(user)

      assert event.event_type == :user_registered
      assert event.aggregate_id == 1
      assert event.aggregate_type == :user
      assert event.payload.email == "test@example.com"
      assert event.payload.name == "Test User"
    end

    test "succeeds with valid user and custom payload" do
      user = %{id: 1, email: "test@example.com", name: "Test User"}

      event = UserEvents.user_registered(user, %{source: :web})

      assert event.payload.source == :web
    end

    test "sets criticality to critical by default" do
      user = %{id: 1, email: "test@example.com", name: "Test User"}

      event = UserEvents.user_registered(user)

      assert event.metadata.criticality == :critical
    end

    test "includes intended_roles in payload when present" do
      user = %{
        id: 1,
        email: "test@example.com",
        name: "Test User",
        intended_roles: [:parent]
      }

      event = UserEvents.user_registered(user)

      assert event.payload.intended_roles == ["parent"]
    end

    test "includes empty list for intended_roles when nil" do
      user = %{id: 1, email: "test@example.com", name: "Test User", intended_roles: nil}

      event = UserEvents.user_registered(user)

      assert event.payload.intended_roles == []
    end

    test "includes empty intended_roles when empty list" do
      user = %{id: 1, email: "test@example.com", name: "Test User", intended_roles: []}

      event = UserEvents.user_registered(user)

      assert event.payload.intended_roles == []
    end

    test "includes multiple roles in intended_roles" do
      user = %{
        id: 1,
        email: "test@example.com",
        name: "Test User",
        intended_roles: [:parent, :provider]
      }

      event = UserEvents.user_registered(user)

      assert event.payload.intended_roles == ["parent", "provider"]
    end

    test "raises when intended_roles is not a list" do
      user = %{id: 1, email: "test@example.com", name: "Test User", intended_roles: "parent"}

      assert_raise ArgumentError,
                   ~r/User.intended_roles must be a list/,
                   fn -> UserEvents.user_registered(user) end
    end

    test "carries no provider_subscription_tier in payload" do
      # Provider tiers removed (ADR-0004)
      user = %{id: 1, email: "test@example.com", name: "Test User", intended_roles: [:provider]}

      event = UserEvents.user_registered(user)

      refute Map.has_key?(event.payload, :provider_subscription_tier)
    end
  end

  describe "user_confirmed/3 validation" do
    test "raises when user.id is nil" do
      user = %{id: nil, email: "test@example.com", confirmed_at: ~U[2024-01-01 12:00:00Z]}

      assert_raise ArgumentError,
                   "User.id cannot be nil for user_confirmed event",
                   fn -> UserEvents.user_confirmed(user) end
    end

    test "raises when user.email is nil" do
      user = %{id: 1, email: nil, confirmed_at: ~U[2024-01-01 12:00:00Z]}

      assert_raise ArgumentError,
                   "User.email cannot be nil or empty for user_confirmed event",
                   fn -> UserEvents.user_confirmed(user) end
    end

    test "raises when user.email is empty string" do
      user = %{id: 1, email: "", confirmed_at: ~U[2024-01-01 12:00:00Z]}

      assert_raise ArgumentError,
                   "User.email cannot be nil or empty for user_confirmed event",
                   fn -> UserEvents.user_confirmed(user) end
    end

    test "raises when user.confirmed_at is nil" do
      user = %{id: 1, email: "test@example.com", confirmed_at: nil}

      assert_raise ArgumentError,
                   "User.confirmed_at cannot be nil for user_confirmed event",
                   fn -> UserEvents.user_confirmed(user) end
    end

    test "succeeds with valid user" do
      confirmed_at = ~U[2024-01-01 12:00:00Z]
      user = %{id: 1, email: "test@example.com", confirmed_at: confirmed_at}

      event = UserEvents.user_confirmed(user)

      assert event.event_type == :user_confirmed
      assert event.aggregate_id == 1
      assert event.aggregate_type == :user
      assert event.payload.email == "test@example.com"
      assert event.payload.confirmed_at == confirmed_at
    end

    test "succeeds with valid user and custom payload" do
      confirmed_at = ~U[2024-01-01 12:00:00Z]
      user = %{id: 1, email: "test@example.com", confirmed_at: confirmed_at}

      event = UserEvents.user_confirmed(user, %{confirmation_token: "abc123"})

      assert event.payload.confirmation_token == "abc123"
    end

    test "includes name and intended_roles in payload" do
      confirmed_at = ~U[2024-01-01 12:00:00Z]

      user = %{
        id: 1,
        email: "test@example.com",
        name: "Test Provider",
        confirmed_at: confirmed_at,
        intended_roles: [:provider]
      }

      event = UserEvents.user_confirmed(user)

      assert event.payload.name == "Test Provider"
      assert event.payload.intended_roles == ["provider"]
      refute Map.has_key?(event.payload, :provider_subscription_tier)
    end

    test "handles nil intended_roles gracefully" do
      confirmed_at = ~U[2024-01-01 12:00:00Z]
      user = %{id: 1, email: "test@example.com", confirmed_at: confirmed_at}

      event = UserEvents.user_confirmed(user)

      assert event.payload.intended_roles == []
    end
  end

  describe "user_email_changed/3 validation" do
    test "raises when previous_email is missing from payload" do
      user = %{id: 1, email: "new@example.com"}

      assert_raise ArgumentError,
                   ~r/requires :previous_email in payload/,
                   fn -> UserEvents.user_email_changed(user, %{}) end
    end

    test "raises when previous_email is nil" do
      user = %{id: 1, email: "new@example.com"}

      assert_raise ArgumentError,
                   ~r/requires :previous_email in payload/,
                   fn -> UserEvents.user_email_changed(user, %{previous_email: nil}) end
    end

    test "raises when previous_email is empty string via guard clause" do
      user = %{id: 1, email: "new@example.com"}

      assert_raise ArgumentError,
                   ~r/requires :previous_email in payload/,
                   fn ->
                     UserEvents.user_email_changed(user, %{previous_email: ""})
                   end
    end

    test "raises when user.id is nil" do
      user = %{id: nil, email: "new@example.com"}

      assert_raise ArgumentError,
                   "User.id cannot be nil for user_email_changed event",
                   fn ->
                     UserEvents.user_email_changed(user, %{previous_email: "old@example.com"})
                   end
    end

    test "raises when user.email is nil" do
      user = %{id: 1, email: nil}

      assert_raise ArgumentError,
                   "User.email cannot be nil or empty for user_email_changed event",
                   fn ->
                     UserEvents.user_email_changed(user, %{previous_email: "old@example.com"})
                   end
    end

    test "raises when user.email is empty string" do
      user = %{id: 1, email: ""}

      assert_raise ArgumentError,
                   "User.email cannot be nil or empty for user_email_changed event",
                   fn ->
                     UserEvents.user_email_changed(user, %{previous_email: "old@example.com"})
                   end
    end

    test "succeeds with valid user and previous_email" do
      user = %{id: 1, email: "new@example.com"}

      event = UserEvents.user_email_changed(user, %{previous_email: "old@example.com"})

      assert event.event_type == :user_email_changed
      assert event.aggregate_id == 1
      assert event.aggregate_type == :user
      assert event.payload.new_email == "new@example.com"
      assert event.payload.previous_email == "old@example.com"
    end

    test "succeeds with valid user and additional payload fields" do
      user = %{id: 1, email: "new@example.com"}

      event =
        UserEvents.user_email_changed(user, %{
          previous_email: "old@example.com",
          change_reason: "user_requested"
        })

      assert event.payload.change_reason == "user_requested"
    end
  end

  describe "user_anonymized/3 validation" do
    test "raises when previous_email is missing from payload" do
      user = %{id: 1, email: "deleted_1@anonymized.local"}

      assert_raise ArgumentError,
                   ~r/requires :previous_email in payload/,
                   fn -> UserEvents.user_anonymized(user, %{}) end
    end

    test "raises when previous_email is nil" do
      user = %{id: 1, email: "deleted_1@anonymized.local"}

      assert_raise ArgumentError,
                   ~r/requires :previous_email in payload/,
                   fn -> UserEvents.user_anonymized(user, %{previous_email: nil}) end
    end

    test "raises when previous_email is empty string via guard clause" do
      user = %{id: 1, email: "deleted_1@anonymized.local"}

      assert_raise ArgumentError,
                   ~r/requires :previous_email in payload/,
                   fn -> UserEvents.user_anonymized(user, %{previous_email: ""}) end
    end

    test "raises when user.id is nil" do
      user = %{id: nil, email: "deleted_nil@anonymized.local"}

      assert_raise ArgumentError,
                   "User.id cannot be nil for user_anonymized event",
                   fn ->
                     UserEvents.user_anonymized(user, %{previous_email: "old@example.com"})
                   end
    end

    test "succeeds with valid user and previous_email" do
      user = %{id: 1, email: "deleted_1@anonymized.local"}

      event = UserEvents.user_anonymized(user, %{previous_email: "old@example.com"})

      assert event.event_type == :user_anonymized
      assert event.aggregate_id == 1
      assert event.aggregate_type == :user
      assert event.payload.anonymized_email == "deleted_1@anonymized.local"
      assert event.payload.previous_email == "old@example.com"
      assert event.payload.anonymized_at
    end

    test "sets criticality to critical by default" do
      user = %{id: 1, email: "deleted_1@anonymized.local"}

      event = UserEvents.user_anonymized(user, %{previous_email: "old@example.com"})

      assert event.metadata.criticality == :critical
    end

    test "succeeds with valid user and additional payload fields" do
      user = %{id: 1, email: "deleted_1@anonymized.local"}

      event =
        UserEvents.user_anonymized(user, %{
          previous_email: "old@example.com",
          deletion_reason: "user_requested"
        })

      assert event.payload.deletion_reason == "user_requested"
    end
  end
end
