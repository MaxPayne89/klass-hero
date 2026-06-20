defmodule KlassHero.StripeFixtures do
  @moduledoc """
  Stripe Identity webhook event payloads, in the real envelope shape Stripe sends
  (`type` + `data.object`), for driving controller and webhook tests. Code-based to match the
  repo's no-JSON-files fixture convention; keep these aligned with real recorded sandbox events.
  """

  @doc "A `identity.verification_session.verified` event with an optional `verified_outputs.dob`."
  def verified_event(session_id, dob \\ %{"day" => 1, "month" => 1, "year" => 1990}) do
    %{
      "id" => "evt_#{System.unique_integer([:positive])}",
      "type" => "identity.verification_session.verified",
      "data" => %{
        "object" => %{
          "id" => session_id,
          "status" => "verified",
          "verified_outputs" => verified_outputs(dob)
        }
      }
    }
  end

  @doc "A `identity.verification_session.requires_input` event."
  def requires_input_event(session_id) do
    session_event(session_id, "requires_input")
  end

  @doc "A `identity.verification_session.canceled` event."
  def canceled_event(session_id) do
    session_event(session_id, "canceled")
  end

  @doc "A `identity.verification_session.processing` event (acked but not acted on)."
  def processing_event(session_id) do
    session_event(session_id, "processing")
  end

  defp session_event(session_id, status) do
    %{
      "id" => "evt_#{System.unique_integer([:positive])}",
      "type" => "identity.verification_session.#{status}",
      "data" => %{"object" => %{"id" => session_id, "status" => status}}
    }
  end

  defp verified_outputs(nil), do: %{"first_name" => "Jenny", "last_name" => "Rosen"}

  defp verified_outputs(dob) do
    %{"first_name" => "Jenny", "last_name" => "Rosen", "dob" => dob}
  end
end
