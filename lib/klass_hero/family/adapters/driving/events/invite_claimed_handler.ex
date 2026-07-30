defmodule KlassHero.Family.Adapters.Driving.Events.InviteClaimedHandler do
  @moduledoc """
  Integration event handler for `:invite_claimed` events from the Enrollment context.

  Thin adapter that enqueues an Oban job for serialized processing.
  The actual domain logic lives in the `ProcessInviteClaim` use case,
  called by `ProcessInviteClaimWorker`. The `family` queue runs with
  concurrency 1, serializing all invite processing globally to prevent
  duplicate child records from concurrent events.
  """

  @behaviour KlassHero.Shared.ForHandlingEvents

  alias KlassHero.Family.Adapters.Driving.Workers.ProcessInviteClaimWorker
  alias KlassHero.Shared.Domain.Events.IntegrationEvent
  alias KlassHero.Shared.Tracing.Context

  require Logger

  @impl true
  def subscribed_events, do: [:invite_claimed]

  @impl true
  def handle_event(%IntegrationEvent{event_type: :invite_claimed, entity_id: invite_id, payload: payload}) do
    args =
      invite_id
      |> build_worker_args(payload)
      |> Context.inject_into_args()

    ProcessInviteClaimWorker.new(args)
    |> Oban.insert()
    |> case do
      {:ok, _job} ->
        Logger.info("[InviteClaimedHandler] Enqueued invite processing",
          invite_id: invite_id,
          user_id: payload.user_id
        )

        :ok

      {:error, reason} ->
        Logger.error("[InviteClaimedHandler] Failed to enqueue",
          invite_id: invite_id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  def handle_event(_event), do: :ignore

  defp build_worker_args(invite_id, payload) do
    %{
      invite_id: invite_id,
      user_id: Map.fetch!(payload, :user_id),
      program_id: Map.fetch!(payload, :program_id),
      child_first_name: Map.get(payload, :child_first_name),
      child_last_name: Map.get(payload, :child_last_name),
      child_date_of_birth: serialize_date(Map.get(payload, :child_date_of_birth)),
      school_grade: Map.get(payload, :school_grade),
      school_name: Map.get(payload, :school_name),
      medical_conditions: Map.get(payload, :medical_conditions),
      nut_allergy: Map.get(payload, :nut_allergy, false)
    }
  end

  # %Date{} must be ISO 8601 for Oban JSON args; worker deserializes in perform/1
  defp serialize_date(%Date{} = date), do: Date.to_iso8601(date)
  defp serialize_date(nil), do: nil
  defp serialize_date(date) when is_binary(date), do: date

  defp serialize_date(other) do
    raise ArgumentError,
          "expected %Date{}, binary, or nil for child_date_of_birth, got: #{inspect(other)}"
  end
end
