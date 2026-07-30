defmodule KlassHero.Shared.ForStagingEvents do
  @moduledoc """
  Port for handing integration events to durable delivery.

  The one method a producer needs, called from inside the transaction that made
  the events true. Implementations must either enqueue durably or raise —
  returning an error would let a producer commit a state change whose events were
  silently dropped, which is the failure this seam exists to remove.
  """

  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  @doc """
  Stages events for delivery, in the order given. Raises if they cannot be staged.
  """
  @callback stage([IntegrationEvent.t()]) :: :ok
end
