defmodule KlassHero.Provider.Profiles.ProviderVerificationTest do
  @moduledoc """
  Tests for provider verification use cases.

  Tests verify/unverify workflows including:
  - State transitions (verified flag and verified_at timestamp)
  - Integration event publishing
  - Error handling for missing providers
  """

  use KlassHero.DataCase, async: true

  import KlassHero.EventTestHelper

  alias KlassHero.AccountsFixtures
  alias KlassHero.Provider
  alias KlassHero.Provider.Domain.Events.ProviderEvents
  alias KlassHero.ProviderFixtures

  setup do
    setup_test_integration_events()
    provider = ProviderFixtures.provider_profile_fixture()
    admin = AccountsFixtures.user_fixture(%{is_admin: true})
    %{provider: provider, admin: admin}
  end

  describe "VerifyProvider.execute/1" do
    test "sets provider as verified", %{provider: provider, admin: admin} do
      params = %{provider_id: provider.id, admin_id: admin.id}

      assert {:ok, verified} = Provider.verify_provider(params.provider_id, params.admin_id)

      assert verified.verified == true
      assert verified.verified_at != nil
    end

    test "sets verified_at timestamp", %{provider: provider, admin: admin} do
      params = %{provider_id: provider.id, admin_id: admin.id}

      {:ok, verified} = Provider.verify_provider(params.provider_id, params.admin_id)

      # Verify the timestamp is set and is a recent DateTime
      assert %DateTime{} = verified.verified_at
      # Timestamp should be within the last minute
      diff = DateTime.diff(DateTime.utc_now(), verified.verified_at, :second)
      assert diff >= 0 and diff < 60
    end

    # The event is still *built* on this path, but since #1195 no consumer is
    # registered for `integration:provider:provider_verified`, so `Outbox.stage/2`
    # drops it before it reaches the outbox — asserting publication here would
    # assert a no-op. The constructor's shape is covered directly instead; the
    # observable outcome of the command is the `verified` fact above.
    test "builds a provider_verified event carrying the provider's identity", %{provider: provider} do
      {:ok, profile} = Provider.get_provider_profile(provider.id)
      event = ProviderEvents.provider_verified(profile, "admin-1")

      assert event.entity_id == provider.id
      assert event.source_context == :provider
      assert event.payload.provider_id == provider.id
    end

    test "returns error when provider not found", %{admin: admin} do
      params = %{provider_id: Ecto.UUID.generate(), admin_id: admin.id}

      assert {:error, :not_found} = Provider.verify_provider(params.provider_id, params.admin_id)
    end

    test "is idempotent - verifying already verified provider succeeds", %{
      provider: provider,
      admin: admin
    } do
      params = %{provider_id: provider.id, admin_id: admin.id}

      # First verification
      {:ok, verified1} = Provider.verify_provider(params.provider_id, params.admin_id)
      assert verified1.verified == true

      # Second verification should still succeed
      {:ok, verified2} = Provider.verify_provider(params.provider_id, params.admin_id)
      assert verified2.verified == true

      # verified_at may be updated or stay the same depending on implementation
      # The key is that the operation succeeds
      assert verified2.verified_at != nil
    end
  end

  describe "UnverifyProvider.execute/1" do
    test "sets provider as unverified", %{provider: provider, admin: admin} do
      # First verify the provider
      Provider.verify_provider(provider.id, admin.id)

      # Then unverify
      params = %{provider_id: provider.id, admin_id: admin.id}
      assert {:ok, unverified} = Provider.unverify_provider(params.provider_id, params.admin_id)

      assert unverified.verified == false
      assert unverified.verified_at == nil
    end

    # See the sibling verify case: the event is built but has no registered consumer
    # since #1195, so `Outbox.stage/2` drops it. Shape is asserted on the constructor.
    test "builds a provider_unverified event carrying the provider's identity", %{provider: provider} do
      {:ok, profile} = Provider.get_provider_profile(provider.id)
      event = ProviderEvents.provider_unverified(profile, "admin-1")

      assert event.entity_id == provider.id
      assert event.source_context == :provider
      assert event.payload.provider_id == provider.id
    end

    test "returns error when provider not found", %{admin: admin} do
      params = %{provider_id: Ecto.UUID.generate(), admin_id: admin.id}

      assert {:error, :not_found} = Provider.unverify_provider(params.provider_id, params.admin_id)
    end

    test "is idempotent - unverifying already unverified provider succeeds", %{
      provider: provider,
      admin: admin
    } do
      # Provider starts unverified by default
      params = %{provider_id: provider.id, admin_id: admin.id}

      # First unverify (already unverified)
      {:ok, unverified1} = Provider.unverify_provider(params.provider_id, params.admin_id)
      assert unverified1.verified == false

      # Second unverify
      {:ok, unverified2} = Provider.unverify_provider(params.provider_id, params.admin_id)
      assert unverified2.verified == false
      assert unverified2.verified_at == nil
    end
  end
end
