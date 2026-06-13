defmodule KlassHero.Accounts.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents do
  @moduledoc """
  Promotes Accounts domain events to integration events for cross-context communication.

  Registered on the Accounts DomainEventBus. When a relevant domain event is
  dispatched, this handler creates the corresponding integration event and
  publishes it via PubSub.

  ## Error strategy

  Propagates publish failures — Identity profile creation depends on user_registered,
  the compensation path for profile existence depends on user_confirmed,
  and the GDPR anonymization cascade depends on user_anonymized.
  """

  alias KlassHero.Accounts.Domain.Events.AccountsIntegrationEvents
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.IntegrationEventPublishing

  @doc false
  @spec handle(DomainEvent.t()) :: :ok | {:error, term()}
  def handle(%DomainEvent{event_type: :user_registered} = event) do
    event.aggregate_id
    |> AccountsIntegrationEvents.user_registered(event.payload)
    |> IntegrationEventPublishing.publish()
  end

  def handle(%DomainEvent{event_type: :user_confirmed} = event) do
    event.aggregate_id
    |> AccountsIntegrationEvents.user_confirmed(event.payload)
    |> IntegrationEventPublishing.publish()
  end

  def handle(%DomainEvent{event_type: :user_anonymized} = event) do
    event.aggregate_id
    |> AccountsIntegrationEvents.user_anonymized(event.payload)
    |> IntegrationEventPublishing.publish()
  end
end
