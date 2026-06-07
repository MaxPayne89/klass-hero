defmodule KlassHero.Accounts.RegistrationProfileCreationIntegrationTest do
  @moduledoc """
  Integration test verifying the full registration → profile creation flow.

  When a user registers, a `user_registered` domain event is dispatched
  synchronously on the Accounts DomainEventBus, promoted to an integration
  event, published via PubSub, and then handled asynchronously by Provider/Family
  EventSubscriber GenServers.

  This test swaps the integration event publisher to the real PubSub publisher
  and grants Ecto Sandbox access to the EventSubscriber GenServers so they can
  access the database within the test's transaction.
  """

  use KlassHero.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias KlassHero.Accounts
  alias KlassHero.Family
  alias KlassHero.Family.Adapters.Driving.Events.FamilyEventHandler
  alias KlassHero.Provider
  alias KlassHero.Provider.Adapters.Driving.Events.ProviderEventHandler
  alias KlassHero.Shared.Adapters.Driven.Events.PubSubIntegrationEventPublisher

  # EventSubscriber GenServers that create profiles in response to user_registered.
  @profile_subscribers [
    FamilyEventHandler,
    ProviderEventHandler
  ]

  setup do
    # Trigger: test config uses TestIntegrationEventPublisher (process dictionary storage)
    # Why: PromoteIntegrationEvents handlers must actually broadcast to PubSub so the
    #      EventSubscriber GenServers receive the events and create profiles
    # Outcome: swap to real PubSub publisher for this test, restore in on_exit
    original_config = Application.get_env(:klass_hero, :integration_event_publisher)

    Application.put_env(:klass_hero, :integration_event_publisher,
      module: PubSubIntegrationEventPublisher,
      pubsub: KlassHero.PubSub
    )

    on_exit(fn ->
      Application.put_env(:klass_hero, :integration_event_publisher, original_config)
    end)

    # Trigger: EventSubscriber GenServers run in separate processes outside the test
    # Why: they need DB access to handle integration events (create parent/provider profiles)
    # Outcome: allow each subscriber to share the test process's sandboxed connection
    Enum.each(@profile_subscribers, fn subscriber_name ->
      case Process.whereis(subscriber_name) do
        nil -> :ok
        pid -> Sandbox.allow(KlassHero.Repo, self(), pid)
      end
    end)

    :ok
  end

  describe "provider registration → profile creation" do
    test "provider profile exists after registration" do
      {:ok, user} =
        Accounts.register_user(%{
          "name" => "Test Provider",
          "email" => "provider-#{System.unique_integer([:positive])}@example.com",
          "intended_roles" => ["provider"]
        })

      assert_eventually(
        fn -> Provider.has_provider_profile?(user.id) end,
        timeout_ms: 2000,
        interval_ms: 50
      )

      assert {:ok, _profile} = Provider.get_provider_by_identity(user.id)
    end

    test "parent profile exists after registration" do
      {:ok, user} =
        Accounts.register_user(%{
          "name" => "Test Parent",
          "email" => "parent-#{System.unique_integer([:positive])}@example.com",
          "intended_roles" => ["parent"]
        })

      assert_eventually(
        fn -> Family.has_parent_profile?(user.id) end,
        timeout_ms: 2000,
        interval_ms: 50
      )

      assert {:ok, _profile} = Family.get_parent_by_identity(user.id)
    end

    test "both profiles exist for dual-role registration" do
      {:ok, user} =
        Accounts.register_user(%{
          "name" => "Dual Role User",
          "email" => "dual-#{System.unique_integer([:positive])}@example.com",
          "intended_roles" => ["parent", "provider"]
        })

      assert_eventually(
        fn ->
          Family.has_parent_profile?(user.id) and Provider.has_provider_profile?(user.id)
        end,
        timeout_ms: 2000,
        interval_ms: 50
      )

      assert {:ok, _parent} = Family.get_parent_by_identity(user.id)
      assert {:ok, _provider} = Provider.get_provider_by_identity(user.id)
    end
  end
end
