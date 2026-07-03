defmodule KlassHero.ProgramCatalog.Adapters.Driven.Projections.VerifiedProvidersTest do
  use KlassHero.DataCase, async: false

  alias KlassHero.AccountsFixtures
  alias KlassHero.ProgramCatalog.Adapters.Driven.Projections.VerifiedProviders
  alias KlassHero.Provider
  alias KlassHero.Provider.ProviderProfile
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  # Use a unique name for each test to avoid conflicts with the supervision tree
  @test_server_name :verified_providers_test

  setup do
    pid = start_supervised!({VerifiedProviders, name: @test_server_name})
    {:ok, pid: pid}
  end

  describe "verified?/1" do
    test "returns false for unknown provider" do
      provider_id = Ecto.UUID.generate()
      refute VerifiedProviders.verified?(provider_id, @test_server_name)
    end

    test "returns true after receiving provider_verified event" do
      provider_id = Ecto.UUID.generate()

      # Trigger: Simulate the integration event published by Provider context
      # Why: VerifiedProviders projection should react to verification events
      # Outcome: Provider ID is added to the in-memory MapSet
      event =
        IntegrationEvent.new(
          :provider_verified,
          :provider,
          :provider,
          provider_id,
          %{provider_id: provider_id, business_name: "Test Business"}
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:provider:provider_verified",
        {:integration_event, event}
      )

      # Synchronize: ensure GenServer has processed the broadcast
      _ = :sys.get_state(@test_server_name)

      assert VerifiedProviders.verified?(provider_id, @test_server_name)
    end

    test "returns false after receiving provider_unverified event" do
      provider_id = Ecto.UUID.generate()

      # Trigger: Provider gets verified first
      # Why: Must be verified before we can unverify
      # Outcome: Provider is in the verified set
      verify_event =
        IntegrationEvent.new(
          :provider_verified,
          :provider,
          :provider,
          provider_id,
          %{provider_id: provider_id, business_name: "Test Business"}
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:provider:provider_verified",
        {:integration_event, verify_event}
      )

      _ = :sys.get_state(@test_server_name)
      assert VerifiedProviders.verified?(provider_id, @test_server_name)

      # Trigger: Provider loses verification
      # Why: Admin revokes verification status
      # Outcome: Provider ID is removed from the in-memory MapSet
      unverify_event =
        IntegrationEvent.new(
          :provider_unverified,
          :provider,
          :provider,
          provider_id,
          %{provider_id: provider_id, business_name: "Test Business"}
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:provider:provider_unverified",
        {:integration_event, unverify_event}
      )

      _ = :sys.get_state(@test_server_name)
      refute VerifiedProviders.verified?(provider_id, @test_server_name)
    end

    test "handles multiple providers independently" do
      provider_1 = Ecto.UUID.generate()
      provider_2 = Ecto.UUID.generate()

      # Verify both providers
      for provider_id <- [provider_1, provider_2] do
        event =
          IntegrationEvent.new(
            :provider_verified,
            :provider,
            :provider,
            provider_id,
            %{provider_id: provider_id}
          )

        Phoenix.PubSub.broadcast(
          KlassHero.PubSub,
          "integration:provider:provider_verified",
          {:integration_event, event}
        )
      end

      _ = :sys.get_state(@test_server_name)
      assert VerifiedProviders.verified?(provider_1, @test_server_name)
      assert VerifiedProviders.verified?(provider_2, @test_server_name)

      # Unverify only provider_1
      unverify_event =
        IntegrationEvent.new(
          :provider_unverified,
          :provider,
          :provider,
          provider_1,
          %{provider_id: provider_1}
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:provider:provider_unverified",
        {:integration_event, unverify_event}
      )

      _ = :sys.get_state(@test_server_name)
      refute VerifiedProviders.verified?(provider_1, @test_server_name)
      assert VerifiedProviders.verified?(provider_2, @test_server_name)
    end
  end

  describe "bootstrap from Provider context" do
    test "bootstraps verified providers from database on startup" do
      admin = AccountsFixtures.user_fixture(%{is_admin: true})

      # Create a provider and verify it directly in the database
      verified_user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])

      {:ok, provider} =
        Provider.create_provider_profile(%{
          identity_id: verified_user.id,
          business_name: "Verified Business"
        })

      {:ok, _} = Provider.verify_provider(provider.id, admin.id)

      # Also create an unverified provider
      unverified_user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])

      {:ok, unverified_provider} =
        Provider.create_provider_profile(%{
          identity_id: unverified_user.id,
          business_name: "Unverified Business"
        })

      # Start a new GenServer instance — it should bootstrap from DB
      bootstrap_name = :"bootstrap_test_#{System.unique_integer([:positive])}"
      bootstrap_pid = start_supervised!({VerifiedProviders, name: bootstrap_name}, id: :bootstrap)

      # Trigger: New GenServer bootstraps from Provider.list_verified_provider_ids/0
      # Why: On cold start, cache must be hydrated from the authoritative source
      # Outcome: Already-verified providers are immediately queryable
      _ = :sys.get_state(bootstrap_pid)

      assert VerifiedProviders.verified?(provider.id, bootstrap_name)
      refute VerifiedProviders.verified?(unverified_provider.id, bootstrap_name)
    end
  end

  describe "rebuild/1" do
    test "rebuilds in-memory cache from database" do
      # Ensure initial bootstrap has completed before inserting test data
      _ = :sys.get_state(@test_server_name)

      admin = AccountsFixtures.user_fixture(%{is_admin: true})

      # Create and verify a provider directly in the database
      verified_user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])

      {:ok, provider} =
        Provider.create_provider_profile(%{
          identity_id: verified_user.id,
          business_name: "Rebuild Test Business"
        })

      {:ok, _} = Provider.verify_provider(provider.id, admin.id)

      # The running test server was started before this provider existed,
      # so it shouldn't know about it yet
      refute VerifiedProviders.verified?(provider.id, @test_server_name)

      # Rebuild should pick it up from the database
      assert :ok = VerifiedProviders.rebuild(@test_server_name)
      assert VerifiedProviders.verified?(provider.id, @test_server_name)
    end
  end

  describe "idempotency" do
    test "duplicate verification events are handled gracefully" do
      provider_id = Ecto.UUID.generate()

      # Send the same verification event twice
      event =
        IntegrationEvent.new(
          :provider_verified,
          :provider,
          :provider,
          provider_id,
          %{provider_id: provider_id}
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:provider:provider_verified",
        {:integration_event, event}
      )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:provider:provider_verified",
        {:integration_event, event}
      )

      _ = :sys.get_state(@test_server_name)

      # Trigger: Multiple verification events for same provider
      # Why: Events may be replayed or duplicated
      # Outcome: MapSet handles duplicates naturally, provider remains verified
      assert VerifiedProviders.verified?(provider_id, @test_server_name)
    end

    test "unverifying non-existent provider is handled gracefully" do
      provider_id = Ecto.UUID.generate()

      # Trigger: Unverify event for provider not in the set
      # Why: Edge case handling - event ordering or missed events
      # Outcome: No crash, operation is a no-op
      event =
        IntegrationEvent.new(
          :provider_unverified,
          :provider,
          :provider,
          provider_id,
          %{provider_id: provider_id}
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:provider:provider_unverified",
        {:integration_event, event}
      )

      _ = :sys.get_state(@test_server_name)
      refute VerifiedProviders.verified?(provider_id, @test_server_name)
    end
  end

  describe "macro invariants after happy-path startup" do
    test "verified_ids is populated and event mutates the cache" do
      name = :"reg_#{System.unique_integer([:positive])}"
      pid = start_supervised!({VerifiedProviders, name: name}, id: :regression_projection)

      # Bootstrap completes — state has the MapSet
      state = :sys.get_state(pid)
      assert state.bootstrapped == true
      assert %MapSet{} = state.verified_ids

      # Send a provider_verified integration event and confirm verified?/2 picks it up
      new_id = Ecto.UUID.generate()

      event =
        IntegrationEvent.new(
          :provider_verified,
          :provider,
          :provider,
          new_id,
          %{provider_id: new_id, business_name: "Regression Business"}
        )

      send(pid, {:integration_event, event})
      # :sys.get_state drains the mailbox (sync fence)
      :sys.get_state(pid)

      assert VerifiedProviders.verified?(new_id, name) == true
    end

    test "rebuild after skip_bootstrap: true populates verified_ids without crashing" do
      # Stealth-bug regression: handle_call(:rebuild) previously used
      # %{state | ... , verified_ids: ...}, which raises KeyError when init state
      # came from skip_bootstrap: true (no :verified_ids key). Map.merge guards this.
      name = :"reg_skip_#{System.unique_integer([:positive])}"

      pid =
        start_supervised!(
          {VerifiedProviders, name: name, skip_bootstrap: true},
          id: :regression_skip_bootstrap
        )

      # Initial state lacks :verified_ids (skip_bootstrap path).
      refute Map.has_key?(:sys.get_state(pid), :verified_ids)

      # Rebuild must NOT crash and must populate verified_ids.
      assert :ok = VerifiedProviders.rebuild(name)

      state = :sys.get_state(pid)
      assert state.bootstrapped == true
      assert %MapSet{} = state.verified_ids
    end
  end
end
