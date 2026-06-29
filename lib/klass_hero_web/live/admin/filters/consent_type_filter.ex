defmodule KlassHeroWeb.Admin.Filters.ConsentTypeFilter do
  @moduledoc false

  use Backpex.Filters.Select

  alias Backpex.Filters.Select
  alias KlassHero.Family.Consent
  alias KlassHeroWeb.Admin.ConsentLive

  @impl Backpex.Filter
  def label, do: "Consent Type"

  @impl Select
  def prompt, do: "All types..."

  @impl Select
  def options(_assigns) do
    Consent.valid_consent_types()
    |> Enum.map(fn type -> {ConsentLive.humanize_consent_type(type), type} end)
  end
end
