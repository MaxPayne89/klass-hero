defmodule KlassHero.ProgramCatalog.Adapters.Driven.Projections.VerifiedProviders do
  @moduledoc """
  In-memory projection of verified provider IDs.

  Maintains a `MapSet` of provider IDs that are verified, enabling fast O(1)
  lookups without database queries. Bootstraps from the Provider context on
  startup and stays in sync via integration events.

  Built on `KlassHero.Shared.Projection` (base). Does NOT use
  `WithBootstrapRetry`: on bootstrap failure the GenServer crashes and the
  supervisor handles the restart, which is the established recovery pattern.

  ## Architecture

  This is a driven adapter — driven by integration events from the Provider
  context. The Program Catalog context uses this projection to enrich program
  data with provider verification status (`ProgramListings` looks it up via
  `verified?/2`).

  ## Event handling

  - `:provider_verified` — adds the provider ID to the MapSet
  - `:provider_unverified` — removes the provider ID from the MapSet
  """

  use KlassHero.Shared.Projection,
    topics: [
      "integration:provider:provider_verified",
      "integration:provider:provider_unverified"
    ]

  alias KlassHero.Provider
  alias KlassHero.Shared.Projection

  @impl Projection
  def bootstrap_impl do
    MapSet.size(load_verified_ids())
  end

  # The macro's handle_info discards handle_event/2's return value without updating state.
  # We cast to self() so MapSet mutation happens in the next handle_cast with access to state.
  # Tests use :sys.get_state/1 as a sync fence that drains the mailbox, so cast ordering is safe.
  @impl Projection
  def handle_event(:provider_verified, event) do
    GenServer.cast(self(), {:add_verified, event.payload.provider_id})
  end

  def handle_event(:provider_unverified, event) do
    GenServer.cast(self(), {:remove_verified, event.payload.provider_id})
  end

  @impl true
  def handle_cast({:add_verified, id}, state) do
    Logger.debug("Provider verified in projection", provider_id: id)
    {:noreply, %{state | verified_ids: MapSet.put(state.verified_ids, id)}}
  end

  def handle_cast({:remove_verified, id}, state) do
    Logger.debug("Provider unverified in projection", provider_id: id)
    {:noreply, %{state | verified_ids: MapSet.delete(state.verified_ids, id)}}
  end

  @doc """
  Returns `true` if the provider ID is in the verified set, `false` otherwise.
  """
  @spec verified?(String.t(), GenServer.name()) :: boolean()
  def verified?(provider_id, name \\ __MODULE__) do
    GenServer.call(name, {:verified?, provider_id})
  end

  # Override to handle :verified? and :rebuild; the macro's default :rebuild does not update verified_ids.
  @impl true
  def handle_call({:verified?, provider_id}, _from, state) do
    {:reply, MapSet.member?(state.verified_ids, provider_id), state}
  end

  def handle_call(:rebuild, _from, state) do
    verified_ids = load_verified_ids()
    Logger.info("#{inspect(__MODULE__)} rebuilt", count: MapSet.size(verified_ids))

    # Map.merge (not %{state | ...}) keeps rebuild safe when started with skip_bootstrap: true (state lacks :verified_ids).
    {:reply, :ok, Map.merge(state, %{bootstrapped: true, verified_ids: verified_ids})}
  end

  # Override: the macro's default apply_bootstrap/1 returns {:noreply, %{state | bootstrapped: true}} with no hook
  # for custom keys; this override also populates verified_ids.
  defp apply_bootstrap(state) do
    verified_ids = load_verified_ids()

    Logger.info("#{inspect(__MODULE__)} projection started",
      count: MapSet.size(verified_ids)
    )

    {:noreply, Map.merge(state, %{bootstrapped: true, verified_ids: verified_ids})}
  end

  defp load_verified_ids do
    case Provider.list_verified_provider_ids() do
      {:ok, ids} -> MapSet.new(ids)
      {:error, reason} -> raise "Failed to bootstrap verified providers: #{inspect(reason)}"
    end
  end
end
