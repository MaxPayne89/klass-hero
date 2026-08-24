defmodule KlassHeroWeb.Helpers.ProviderDisplay do
  @moduledoc """
  Shared provider lookup for every surface that renders `<.program_card>`.

  Centralizes the name-plus-trust-state pair so the home page, the programs
  listing and the parent dashboard resolve a provider the same way. Sibling
  LiveViews rendering the same card have drifted before when each kept its own
  copy of a lookup.

  Both reads are batched per render — one `IN` query each over the distinct
  provider ids on the page — so adding the provider row to a card costs two
  queries, not two per card.
  """

  alias KlassHero.Provider
  alias KlassHeroWeb.Presenters.ProviderPresenter

  require Logger

  @unknown %{name: nil, trust: :unverified}

  @doc """
  Batch-resolves `%{provider_id => %{name:, trust:}}` for the given programs.

  Accepts anything carrying a `provider_id` — `%ProgramListing{}` read models or
  `%Program{}` write models both work.
  """
  @spec for_programs([%{provider_id: String.t()}]) ::
          %{String.t() => %{name: String.t() | nil, trust: Provider.trust_state()}}
  def for_programs(programs) do
    provider_ids = programs |> Enum.map(& &1.provider_id) |> Enum.uniq()
    names = Provider.get_business_names(provider_ids)
    trust_states = Provider.get_trust_states(provider_ids)

    Map.new(provider_ids, fn id ->
      {id, %{name: Map.get(names, id), trust: Map.get(trust_states, id, :unverified)}}
    end)
  end

  @doc """
  Looks a program's provider out of `for_programs/1`'s result.

  Falls back to an unnamed, unverified provider so a card whose provider row
  cannot be resolved hides the row rather than rendering a blank one.
  """
  @spec fetch(map(), %{provider_id: String.t()}) :: %{
          name: String.t() | nil,
          trust: Provider.trust_state()
        }
  def fetch(providers, program), do: Map.get(providers, program.provider_id, @unknown)

  @doc """
  Builds the public hero view for one provider, or `nil` when there is none to show.

  Both `provider_hero/1` variants take this map. `Provider.get_public_profile/1`
  owns which profiles are public; this adds the trust state and the presenter.

  The trust read is rescued so a vetting-lookup failure costs the badge rather
  than the whole card — the badge is additive, the identity is the content, and
  degrading to `:unverified` under-claims rather than over-claims.
  """
  @spec public_view(term()) :: map() | nil
  def public_view(provider_id) do
    case Provider.get_public_profile(provider_id) do
      {:ok, profile} -> ProviderPresenter.to_public_view(profile, trust_state(provider_id))
      {:error, :not_found} -> nil
    end
  end

  # get_trust_states/1 is batch-only; a missing entry means unverified.
  defp trust_state(provider_id) do
    [provider_id]
    |> Provider.get_trust_states()
    |> Map.get(provider_id, :unverified)
  rescue
    error ->
      Logger.warning("trust state lookup failed for provider #{provider_id}: #{inspect(error)}")
      :unverified
  end

  @doc "The fallback used when a provider cannot be resolved."
  @spec unknown() :: %{name: nil, trust: :unverified}
  def unknown, do: @unknown
end
