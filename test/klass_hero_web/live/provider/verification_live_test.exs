defmodule KlassHeroWeb.Provider.VerificationLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias KlassHero.ProviderFixtures
  alias KlassHero.Shared.Domain.Events.DomainEvent

  setup :register_and_log_in_provider

  describe ":verification — not started" do
    test "renders the start-verification button when no identity verification exists", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/verification")

      assert has_element?(view, "#identity-verify-start")
    end
  end

  describe ":verification — read state" do
    test "renders in-progress for a processing session", %{conn: conn, provider: provider} do
      ProviderFixtures.identity_verification_fixture(provider_id: provider.id, status: :processing)

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/verification")

      assert has_element?(view, "#identity-verify-in-progress")
      refute has_element?(view, "#identity-verify-start")
    end

    test "renders approved for a passed verification", %{conn: conn, provider: provider} do
      ProviderFixtures.identity_verification_fixture(
        provider_id: provider.id,
        status: :verified,
        outcome: :pass
      )

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/verification")

      assert has_element?(view, "#identity-verify-approved")
    end

    test "renders failed with a retry button for a failed verification", %{
      conn: conn,
      provider: provider
    } do
      ProviderFixtures.identity_verification_fixture(
        provider_id: provider.id,
        status: :verified,
        outcome: :fail,
        failure_reason: "under_18"
      )

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/verification")

      assert has_element?(view, "#identity-verify-failed")
      assert has_element?(view, "#identity-verify-retry")
      # under_18 is terminal — copy says so rather than implying a retry will help.
      assert has_element?(view, "#identity-verify-failed", "18 and over")
    end
  end

  describe ":verification — live updates" do
    test "flips in-progress to approved on this provider's passed event", %{
      conn: conn,
      provider: provider
    } do
      iv = ProviderFixtures.identity_verification_fixture(provider_id: provider.id, status: :processing)

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/verification")
      assert has_element?(view, "#identity-verify-in-progress")

      # Mirror the webhook: truth is updated (a passed record exists) before the event fires.
      ProviderFixtures.identity_verification_fixture(
        provider_id: provider.id,
        status: :verified,
        outcome: :pass
      )

      event =
        DomainEvent.new(:identity_verification_passed, iv.id, :identity_verification, %{
          provider_id: provider.id
        })

      send(view.pid, {:domain_event, event})

      assert has_element?(view, "#identity-verify-approved")
    end

    test "ignores an identity event for a different provider", %{conn: conn, provider: provider} do
      ProviderFixtures.identity_verification_fixture(provider_id: provider.id, status: :processing)

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/verification")
      assert has_element?(view, "#identity-verify-in-progress")

      event =
        DomainEvent.new(:identity_verification_passed, Ecto.UUID.generate(), :identity_verification, %{
          provider_id: Ecto.UUID.generate()
        })

      send(view.pid, {:domain_event, event})

      # Still in-progress: the event was for someone else, so no re-fetch happened.
      assert has_element?(view, "#identity-verify-in-progress")
      refute has_element?(view, "#identity-verify-approved")
    end
  end
end
