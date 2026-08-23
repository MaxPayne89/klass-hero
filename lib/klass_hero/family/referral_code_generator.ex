defmodule KlassHero.Family.ReferralCodeGenerator do
  @moduledoc """
  Domain service for generating user referral codes.
  Referral codes follow the format: {FIRST_NAME}-{LOCATION}-{YEAR_SUFFIX}
  """

  @doc """
  Generates a referral code for a user.
  """
  def generate(name, opts \\ []) when is_binary(name) do
    first_name = extract_first_name(name)
    location = Keyword.get(opts, :location, "BERLIN")
    year_suffix = Keyword.get(opts, :year_suffix, default_year_suffix())

    "#{String.upcase(first_name)}-#{location}-#{year_suffix}"
  end

  defp extract_first_name(name) do
    name
    |> String.split(" ", parts: 2)
    |> List.first()
    |> String.trim()
  end

  defp default_year_suffix do
    Date.utc_today().year
    |> rem(100)
    |> Integer.to_string()
    |> String.pad_leading(2, "0")
  end
end
