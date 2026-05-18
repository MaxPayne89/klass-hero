defmodule KlassHero.Enrollment.Adapters.Driving.Events.EventHandlers.NotifyLiveViews do
  @moduledoc """
  Routes Enrollment domain events to PubSub topics for LiveView updates.

  `:enrollment_confirmed` events are scoped per-provider via
  `provider_scoped_topic/2`. All other events fall back to the shared default
  topic (`"<aggregate>:<event>"`).
  """

  alias KlassHero.Shared.Adapters.Driven.Events.EventHandlers.NotifyLiveViews,
    as: SharedNotifyLiveViews

  alias KlassHero.Shared.Domain.Events.DomainEvent

  @spec handle(DomainEvent.t()) :: :ok
  def handle(%DomainEvent{} = event) do
    SharedNotifyLiveViews.safe_publish(event, derive_topic(event))
  end

  @doc """
  Single source of truth for the provider-scoped Enrollment topic format.

  Both publisher (`derive_topic/1`) and subscribers (e.g. `DashboardLive`)
  call this so the topic string never drifts between sides.
  """
  @spec provider_scoped_topic(atom(), String.t()) :: String.t()
  def provider_scoped_topic(event_type, provider_id) when is_atom(event_type) and is_binary(provider_id) do
    "enrollment:#{event_type}:provider:#{provider_id}"
  end

  @spec derive_topic(DomainEvent.t()) :: String.t()
  def derive_topic(%DomainEvent{event_type: :enrollment_confirmed, payload: %{provider_id: pid}}) when is_binary(pid),
    do: provider_scoped_topic(:enrollment_confirmed, pid)

  def derive_topic(%DomainEvent{} = event), do: SharedNotifyLiveViews.derive_topic(event)

  defdelegate build_topic(aggregate_type, event_type), to: SharedNotifyLiveViews
end
