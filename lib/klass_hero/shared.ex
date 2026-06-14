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
      CommandResult,
      Entitlements,
      ErrorIds,
      SubscriptionTiers,
      Domain.Events.DomainEvent,
      Domain.Events.IntegrationEvent,
      Domain.Ports.Driving.ForHandlingEvents,
      Domain.Ports.Driving.ForHandlingIntegrationEvents,
      Domain.Models.PersistenceSupport,
      Domain.Types.Money,
      Domain.Validation,
      Domain.Types.Pagination.PageResult,
      DomainEventBus,
      EventPublishing,
      IntegrationEventPublishing,
      EventDispatchHelper,
      NameUtils,
      Projection,
      Projection.WithBootstrapRetry,
      Projection.WithDomainEvents,
      FeatureFlags,
      Adapters.Driven.Events.EventHandlers.NotifyLiveViews,
      Adapters.Driven.Events.RetryHelpers,
      Adapters.Driven.Persistence.EctoErrorHelpers,
      Adapters.Driven.Persistence.MapperHelpers,
      Adapters.Driven.Persistence.RepositoryHelpers,
      EmailHtml,
      Interaction,
      Interaction.Kind,
      Interaction.Kind.Db,
      Interaction.Kind.Email,
      Interaction.Kind.FeatureFlags,
      Interaction.Kind.Http,
      Interaction.Kind.S3,
      Interaction.TelemetryLogger,
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
