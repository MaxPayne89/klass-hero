defmodule KlassHeroWeb.Helpers.ProviderBranding do
  @moduledoc """
  Reads the branding section of the provider profile forms (#1302).

  Both provider-facing forms — profile completion and dashboard edit — capture
  the same branding fields, so both read them the same way here. Splitting that
  across the two LiveViews is what let the earlier version of this change grow
  three hand-kept copies of the same field list.

  `cover_image_url` is deliberately absent: it comes from an upload, not a form
  param, and each form handles its own upload.
  """

  alias KlassHero.Provider.ProviderProfile

  @param_fields ProviderProfile.branding_fields() -- [:cover_image_url]

  @doc """
  Extracts the branding fields from raw form params, keyed by schema field.

  A blank input means "unset", so it maps to `nil` rather than `""` — that is
  what makes clearing a social link actually clear it instead of failing
  validation on an empty string.
  """
  @spec attrs_from_params(map()) :: map()
  def attrs_from_params(params) when is_map(params) do
    for field <- @param_fields,
        # Explicit membership test, not the bare-assignment filter a `for` would
        # otherwise apply — a missing key should be absent from the result for a
        # visible reason, not because nil silently dropped the element (#1408).
        Map.has_key?(params, Atom.to_string(field)),
        into: %{},
        do: {field, blank_to_nil(params[Atom.to_string(field)])}
  end

  @doc """
  The social-link fields this provider has already filled in.

  Seeds which rows the branding form shows on first render. A field with no
  value is offered by the picker instead, so the form starts at the length of
  what the provider actually has.
  """
  @spec filled_networks(map()) :: [atom()]
  def filled_networks(provider) do
    # `Enum.filter`, not a `for` with an assignment: a bare `value = ...` clause
    # in a comprehension filters on truthiness as well as binding, so a nil
    # column would drop out for a reason the code does not state (#1408).
    Enum.filter(ProviderProfile.social_link_fields(), fn field ->
      case Map.get(provider, field) do
        value when is_binary(value) -> String.trim(value) != ""
        _ -> false
      end
    end)
  end

  @doc """
  Adds a network to the revealed list, given the picker's raw param.

  Resolves the string against `social_link_fields/0` rather than calling
  `String.to_existing_atom/1` on it: the param comes from the client, and an
  unknown value should be ignored, not raise.
  """
  @spec reveal([atom()], String.t()) :: [atom()]
  def reveal(revealed, network) when is_binary(network) do
    case Enum.find(ProviderProfile.social_link_fields(), &(Atom.to_string(&1) == network)) do
      nil -> revealed
      field -> Enum.uniq(revealed ++ [field])
    end
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value
end
