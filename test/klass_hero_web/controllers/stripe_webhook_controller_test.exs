defmodule KlassHeroWeb.StripeWebhookControllerTest do
  use KlassHeroWeb.ConnCase, async: false

  alias KlassHero.Provider.IdentityVerification
  alias KlassHero.ProviderFixtures
  alias KlassHero.Repo
  alias KlassHero.StripeFixtures

  setup do
    provider = ProviderFixtures.provider_profile_fixture()
    seed_processing(provider.id, "vs_ctrl")
    %{provider: provider}
  end

  defp seed_processing(provider_id, session_id) do
    %IdentityVerification{}
    |> IdentityVerification.create_changeset(%{
      id: Ecto.UUID.generate(),
      provider_id: provider_id,
      stripe_session_id: session_id,
      status: :processing
    })
    |> Repo.insert!()
  end

  defp reload(session_id), do: Repo.get_by!(IdentityVerification, stripe_session_id: session_id)

  defp post_event(conn, event), do: post(conn, ~p"/webhooks/stripe", event)

  describe "POST /webhooks/stripe" do
    test "a verified event for an adult advances the record to a pass", %{conn: conn} do
      conn = post_event(conn, StripeFixtures.verified_event("vs_ctrl", %{"day" => 1, "month" => 1, "year" => 1990}))

      assert json_response(conn, 200)
      iv = reload("vs_ctrl")
      assert iv.status == :verified
      assert iv.outcome == :pass
    end

    test "a verified event for a minor fails closed", %{conn: conn} do
      conn = post_event(conn, StripeFixtures.verified_event("vs_ctrl", %{"day" => 1, "month" => 1, "year" => 2015}))

      assert json_response(conn, 200)
      iv = reload("vs_ctrl")
      assert iv.outcome == :fail
      assert iv.failure_reason == "under_18"
    end

    test "a requires_input event fails the record", %{conn: conn} do
      conn = post_event(conn, StripeFixtures.requires_input_event("vs_ctrl"))

      assert json_response(conn, 200)
      iv = reload("vs_ctrl")
      assert iv.status == :requires_input
      assert iv.outcome == :fail
    end

    test "a processing event is acked but does not change the record", %{conn: conn} do
      conn = post_event(conn, StripeFixtures.processing_event("vs_ctrl"))

      assert json_response(conn, 200)
      assert reload("vs_ctrl").status == :processing
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
