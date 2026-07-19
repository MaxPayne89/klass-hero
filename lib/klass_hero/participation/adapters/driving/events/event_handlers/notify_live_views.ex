defmodule KlassHero.Participation.Adapters.Driving.Events.EventHandlers.NotifyLiveViews do
  @moduledoc """
  Routes Participation domain events to PubSub topics for LiveView real-time updates.

  Publishes each event to two topics:
  1. Generic topic (`participation:event_type`) — for context-wide subscribers
  2. Provider-specific topic (`participation:provider:provider_id`) — for provider-scoped LiveViews

  Provider ID is resolved via the ForResolvingProgramProvider ACL port.
  If resolution fails, the provider-specific publish is skipped (best-effort).

  Provider-specific routing applies only to session and attendance events (which carry
  `program_id` in their payload). Session note events use a different aggregate type
  and carry `provider_id` directly — they skip provider-specific routing and are delivered
  only via the generic topic.
  """

  alias KlassHero.Participation.Adapters.Driven.ACL.ProgramProviderResolver

  alias KlassHero.Shared.Adapters.Driven.Events.EventHandlers.NotifyLiveViews,
    as: SharedNotifyLiveViews

  alias KlassHero.Shared.Domain.Events.DomainEvent

  require Logger

  @doc "Handles a domain event by publishing to generic and provider-specific topics."
  @spec handle(DomainEvent.t()) :: :ok
  def handle(%DomainEvent{} = event) do
    generic_topic = SharedNotifyLiveViews.derive_topic(event)
    SharedNotifyLiveViews.safe_publish(event, generic_topic)

    publish_to_provider_topic(event)

    :ok
  end

  @doc "Derives a PubSub topic from a domain event's aggregate_type and event_type."
  @spec derive_topic(DomainEvent.t()) :: String.t()
  defdelegate derive_topic(event), to: SharedNotifyLiveViews

  @doc "Builds a PubSub topic string from aggregate type and event type atoms."
  @spec build_topic(atom(), atom()) :: String.t()
  defdelegate build_topic(aggregate_type, event_type), to: SharedNotifyLiveViews

  @doc "Builds the provider-scoped participation topic. The single source both the publisher (here) and subscribers (via the `Participation` facade) use."
  @spec provider_topic(String.t()) :: String.t()
  def provider_topic(provider_id), do: "participation:provider:#{provider_id}"

  defp publish_to_provider_topic(%DomainEvent{payload: payload} = event) do
    case Map.fetch(payload, :program_id) do
      {:ok, program_id} ->
        resolve_and_publish(event, program_id)

      :error ->
        Logger.debug(
          "[Participation.NotifyLiveViews] Skipping provider topic — no program_id in payload",
          event_type: event.event_type
        )
    end
  end

  defp resolve_and_publish(event, program_id) do
    case ProgramProviderResolver.resolve_provider_id(program_id) do
      {:ok, provider_id} ->
        SharedNotifyLiveViews.safe_publish(event, provider_topic(provider_id))

      {:error, reason} ->
        # Best-effort: generic topic already published. Demoted from :warning — sustained
        # failures belong in metrics/alerts. Can fire in tests due to EventSubscriber
        # GenServers running outside the sandbox after global Application.put_env leaks.
        Logger.debug(
          "[Participation.NotifyLiveViews] Could not resolve provider for program",
          program_id: program_id,
          event_type: event.event_type,
          reason: reason
        )
    end
  end
end
