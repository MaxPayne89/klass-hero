defmodule KlassHero.Shared do
  @moduledoc """
  Shared kernel — cross-cutting utilities used by all bounded contexts.

  Contains domain event infrastructure, error IDs, storage adapters,
  and common domain types.
  """

  use Boundary,
    top_level?: true,
    deps: [KlassHero],
    exports: [
      Categories,
      Entitlements,
      ErrorIds,
      SubscriptionTiers,
      Domain.Events.DomainEvent,
      Domain.Events.IntegrationEvent,
      Domain.Ports.Driving.ForHandlingEvents,
      Domain.Ports.Driving.ForHandlingIntegrationEvents,
      Domain.Types.Money,
      Domain.Types.Pagination.PageResult,
      DomainEventBus,
      EventPublishing,
      IntegrationEventPublishing,
      EventDispatchHelper,
      NameUtils,
      FeatureFlags,
      Adapters.Driven.Events.EventHandlers.NotifyLiveViews,
      Adapters.Driven.Events.RetryHelpers,
      Adapters.Driven.Persistence.EctoErrorHelpers,
      Adapters.Driven.Persistence.MapperHelpers,
      Adapters.Driven.Persistence.RepositoryHelpers,
      EmailHtml,
      RateLimitedEmailWorker,
      Storage,
      Tracing,
      Tracing.Context,
      Tracing.LiveViewHook,
      Tracing.ObanEnqueue,
      Tracing.Plug,
      Tracing.TracedWorker
    ]
end
