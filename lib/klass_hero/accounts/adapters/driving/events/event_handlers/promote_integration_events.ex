defmodule KlassHero.Accounts.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents do
  @moduledoc """
  Maps Accounts domain events to their integration events.

  `promote/1` is pure — `KlassHero.Shared.Outbox` calls it inside the producer's
  transaction so the integration event exists before anything commits. Returning
  `nil` for an unmapped event type reproduces today's semantics exactly: an event
  with no registration was never promoted either.

  `handle/1` is the bus-registered wrapper that promotes and publishes; it goes
  when this context's producers move to the outbox.

  ## Error strategy

  The bus path propagates publish failures — Family profile creation depends on
  `user_registered`, the compensation path for profile existence depends on
  `user_confirmed`, and the GDPR anonymization cascade depends on
  `user_anonymized`. The outbox replaces that with Oban retry.
  """

  alias KlassHero.Accounts.Domain.Events.AccountsIntegrationEvents
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.Domain.Events.IntegrationEvent
  alias KlassHero.Shared.IntegrationEventPublishing

  @spec promote(DomainEvent.t()) :: IntegrationEvent.t() | nil
  def promote(%DomainEvent{event_type: :user_registered} = event) do
    AccountsIntegrationEvents.user_registered(event.aggregate_id, event.payload)
  end

  def promote(%DomainEvent{event_type: :user_confirmed} = event) do
    AccountsIntegrationEvents.user_confirmed(event.aggregate_id, event.payload)
  end

  def promote(%DomainEvent{event_type: :user_anonymized} = event) do
    AccountsIntegrationEvents.user_anonymized(event.aggregate_id, event.payload)
  end

  def promote(%DomainEvent{}), do: nil

  @doc false
  @spec handle(DomainEvent.t()) :: :ok | {:error, term()}
  def handle(%DomainEvent{} = event) do
    case promote(event) do
      %IntegrationEvent{} = integration_event -> IntegrationEventPublishing.publish(integration_event)
      nil -> :ok
    end
  end
end
