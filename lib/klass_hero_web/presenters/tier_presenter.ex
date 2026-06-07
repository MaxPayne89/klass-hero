defmodule KlassHeroWeb.Presenters.TierPresenter do
  @moduledoc """
  Shared presentation logic for subscription tier display data.

  Translates canonical tier limits from `KlassHero.Shared.Entitlements` into
  UI-ready strings for subscription pages, registration selectors,
  and anywhere else tier information appears in the frontend.

  ## Usage

      alias KlassHeroWeb.Presenters.TierPresenter

      # Full tier cards for subscription page
      tiers = TierPresenter.subscription_tiers()

      # Compact options for registration selector
      options = TierPresenter.registration_tier_options()

      # Individual label
      TierPresenter.tier_label(:professional)  #=> "Professional"
  """

  use Gettext, backend: KlassHeroWeb.Gettext

  alias KlassHero.Shared.Entitlements

  @provider_tiers Entitlements.provider_tiers()

  # -- Individual tier attributes (multi-clause pattern matching) --

  @doc "Human-readable tier name."
  @spec tier_label(atom()) :: String.t()
  def tier_label(:starter), do: gettext("Starter")
  def tier_label(:professional), do: gettext("Professional")
  def tier_label(:business_plus), do: gettext("Business Plus")

  @doc "Human-readable tier name with 'Plan' suffix for flash messages and badges."
  @spec tier_plan_label(atom()) :: String.t()
  def tier_plan_label(tier), do: gettext("%{name} Plan", name: tier_label(tier))

  @doc "Short tagline describing the tier's target audience."
  @spec tier_subtitle(atom()) :: String.t()
  def tier_subtitle(:starter), do: gettext("Get started for free")
  def tier_subtitle(:professional), do: gettext("For growing businesses")
  def tier_subtitle(:business_plus), do: gettext("For established providers")

  @doc "Price string for the tier."
  @spec tier_price(atom()) :: String.t()
  def tier_price(:starter), do: gettext("Free")
  def tier_price(:professional), do: "€19"
  def tier_price(:business_plus), do: "€49"

  @doc "Billing period string."
  @spec tier_period(atom()) :: String.t()
  def tier_period(:starter), do: gettext("forever")
  def tier_period(:professional), do: gettext("month")
  def tier_period(:business_plus), do: gettext("month")

  @doc """
  Feature list for a tier, derived from `Entitlements.provider_tier_info/1`.

  Translates raw limits (e.g. `max_programs: 2`) into human-readable
  strings (e.g. "2 programs").
  """
  @spec tier_features(atom()) :: [String.t()]
  def tier_features(tier) when tier in @provider_tiers do
    info = Entitlements.provider_tier_info(tier)

    [
      format_program_limit(info.max_programs),
      format_commission(info.commission_rate),
      format_media(info.media),
      format_team_seats(info.team_seats)
    ]
    |> maybe_append(info.can_initiate_messaging, gettext("Direct messaging"))
    |> maybe_append(:promotional in info.media, gettext("Promotional content"))
  end

  # -- Composite builders for specific UI contexts --

  @doc """
  Returns tier card data for the subscription management page.

  Each map contains: `:key`, `:title`, `:subtitle`, `:price`, `:period`, `:features`.
  """
  @spec subscription_tiers() :: [map()]
  def subscription_tiers do
    Enum.map(Entitlements.provider_tiers(), fn tier ->
      %{
        key: tier,
        title: tier_label(tier),
        subtitle: tier_subtitle(tier),
        price: tier_price(tier),
        period: tier_period(tier),
        features: tier_features(tier)
      }
    end)
  end

  # -- Private formatting helpers --

  defp format_program_limit(:unlimited), do: gettext("Unlimited programs")
  defp format_program_limit(n), do: ngettext("1 program", "%{count} programs", n)

  defp format_commission(rate) do
    percent = round(rate * 100)
    gettext("%{percent}% commission", percent: percent)
  end

  defp format_media([:avatar]), do: gettext("Avatar media only")

  defp format_media(media) when is_list(media) do
    # Trigger: tier allows multiple media types beyond avatar
    # Why: feature list should highlight the accessible media types without :promotional
    #      (promotional is listed separately as a distinct feature)
    # Outcome: human-readable, fully-translatable media summary for the tier card
    non_promotional = Enum.reject(media, &(&1 == :promotional))

    case Enum.sort(non_promotional) do
      [:avatar, :gallery, :video] ->
        gettext("All media types")

      types ->
        labels = Enum.map_join(types, ", ", &media_label/1)
        gettext("%{media_types} media", media_types: labels)
    end
  end

  defp media_label(:avatar), do: gettext("Avatar")
  defp media_label(:gallery), do: gettext("Gallery")
  defp media_label(:video), do: gettext("Video")

  defp format_team_seats(:unlimited), do: gettext("Unlimited team seats")
  defp format_team_seats(1), do: ngettext("1 team seat", "%{count} team seats", 1)
  defp format_team_seats(n), do: ngettext("1 team seat", "%{count} team seats", n)

  defp maybe_append(list, true, item), do: list ++ [item]
  defp maybe_append(list, false, _item), do: list
end
