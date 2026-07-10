defmodule KlassHeroWeb.StripeWebhookController do
  use KlassHeroWeb, :controller

  alias KlassHero.Provider

  require Logger

  @doc """
  Receives Stripe Identity webhook events (signature already verified by the pipeline plug).

  Terminal session events (`verified` / `requires_input` / `canceled`) are normalised and
  handed to `Provider.record_identity_verification_outcome/1`; `processing` and any other
  event are acknowledged with 200 but not acted on. Always replies 200 — a non-2xx would
  make Stripe retry indefinitely.
  """
  def handle(conn, %{"type" => type, "data" => %{"object" => object}}) do
    case normalize(type, object) do
      {:ok, outcome} ->
        Provider.record_identity_verification_outcome(Map.put(outcome, :today, Date.utc_today()))

      :ignore ->
        Logger.debug("Ignoring Stripe webhook event", type: type)
    end

    json(conn, %{received: true})
  end

  def handle(conn, _params), do: json(conn, %{received: true})

  defp normalize("identity.verification_session.verified", object) do
    {:ok, %{session_id: object["id"], stripe_status: :verified, dob: extract_dob(object)}}
  end

  defp normalize("identity.verification_session.requires_input", object) do
    {:ok, %{session_id: object["id"], stripe_status: :requires_input, dob: nil}}
  end

  defp normalize("identity.verification_session.canceled", object) do
    {:ok, %{session_id: object["id"], stripe_status: :canceled, dob: nil}}
  end

  defp normalize(_type, _object), do: :ignore

  defp extract_dob(%{"verified_outputs" => %{"dob" => %{"day" => d, "month" => m, "year" => y}}}) do
    %{day: d, month: m, year: y}
  end

  defp extract_dob(_object), do: nil
end
