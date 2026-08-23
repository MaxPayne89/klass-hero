defmodule KlassHero.SocialLinks do
  @moduledoc """
  Klass Hero's own social accounts, from application config, plus the supported
  network set both Klass Hero and providers share.

  Same shape as `KlassHero.Contact`: a config-backed accessor so a surface renders
  what is set and omits what is not.

  No accounts exist yet, so `all/0` returns `[]` and the footer's icon row does not
  render. Adding one is a single line in `config/config.exs`.
  """

  @networks [:instagram, :facebook, :tiktok, :youtube, :linkedin]

  @labels %{
    instagram: "Instagram",
    facebook: "Facebook",
    tiktok: "TikTok",
    youtube: "YouTube",
    linkedin: "LinkedIn"
  }

  @doc """
  Supported networks, in display order.

  The single source for the set. `kh_social_icon/1` and
  `ProviderPresenter.social_networks/0` both assert against it at compile time.
  """
  @spec networks() :: [atom()]
  def networks, do: @networks

  @doc """
  A network's brand name.

  Never run through gettext — translating "Instagram" would be wrong in every
  locale.
  """
  @spec label(atom()) :: String.t()
  def label(network), do: Map.fetch!(@labels, network)

  @doc """
  Klass Hero's configured accounts as `{network, label, url}`, omitting any unset
  or blank.

  Same shape as `ProviderPresenter.social_links/1` so one row component renders
  either source.
  """
  @spec all() :: [{atom(), String.t(), String.t()}]
  def all do
    for network <- @networks,
        url = get(network),
        is_binary(url),
        trimmed = String.trim(url),
        trimmed != "",
        do: {network, label(network), trimmed}
  end

  defp get(key) do
    :klass_hero
    |> Application.get_env(:social_links, [])
    |> Keyword.get(key)
  end
end
