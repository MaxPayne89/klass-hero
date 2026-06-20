defmodule KlassHeroWeb.StripeWebhookControllerTest do
  use KlassHeroWeb.ConnCase, async: true

  alias KlassHero.Provider.Adapters.Driven.Persistence.Repositories.IdentityVerificationRepository
  alias KlassHero.Provider.Domain.Models.IdentityVerification
  alias KlassHero.ProviderFixtures
  alias KlassHero.StripeFixtures

  setup do
    provider = ProviderFixtures.provider_profile_fixture()

    {:ok, _iv} =
      IdentityVerificationRepository.create(
        IdentityVerification.new(%{provider_id: provider.id, stripe_session_id: "vs_ctrl"})
      )

    %{provider: provider}
  end

  defp post_event(conn, event), do: post(conn, ~p"/webhooks/stripe", event)

  describe "POST /webhooks/stripe" do
    test "a verified event for an adult advances the record to a pass", %{conn: conn} do
      conn = post_event(conn, StripeFixtures.verified_event("vs_ctrl", %{"day" => 1, "month" => 1, "year" => 1990}))

      assert json_response(conn, 200)
      {:ok, iv} = IdentityVerificationRepository.get_by_session_id("vs_ctrl")
      assert iv.status == :verified
      assert iv.outcome == :pass
    end

    test "a verified event for a minor fails closed", %{conn: conn} do
      conn = post_event(conn, StripeFixtures.verified_event("vs_ctrl", %{"day" => 1, "month" => 1, "year" => 2015}))

      assert json_response(conn, 200)
      {:ok, iv} = IdentityVerificationRepository.get_by_session_id("vs_ctrl")
      assert iv.outcome == :fail
      assert iv.failure_reason == "under_18"
    end

    test "a requires_input event fails the record", %{conn: conn} do
      conn = post_event(conn, StripeFixtures.requires_input_event("vs_ctrl"))

      assert json_response(conn, 200)
      {:ok, iv} = IdentityVerificationRepository.get_by_session_id("vs_ctrl")
      assert iv.status == :requires_input
      assert iv.outcome == :fail
    end

    test "a processing event is acked but does not change the record", %{conn: conn} do
      conn = post_event(conn, StripeFixtures.processing_event("vs_ctrl"))

      assert json_response(conn, 200)
      {:ok, iv} = IdentityVerificationRepository.get_by_session_id("vs_ctrl")
      assert iv.status == :processing
    end

    test "an event for an unknown session is acked with 200", %{conn: conn} do
      conn = post_event(conn, StripeFixtures.canceled_event("vs_unknown"))
      assert json_response(conn, 200)
    end

    test "an unrecognised event type is acked with 200", %{conn: conn} do
      conn = post(conn, ~p"/webhooks/stripe", %{"type" => "charge.succeeded", "data" => %{"object" => %{}}})
      assert json_response(conn, 200)
    end
  end
end
