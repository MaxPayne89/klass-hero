defmodule KlassHeroWeb.Helpers.Greeting do
  @moduledoc """
  Time-of-day greeting for the parent dashboard.

  All `DateTime` inputs are UTC; the helper shifts to the display timezone
  (default `Europe/Berlin`, configurable via `:default_tz`) so DST is
  handled by `tz`.

  Pure functions — no side effects, no DB. Composition lives in the caller
  (typically a LiveView mount) so this module stays trivially testable.
  """

  use Gettext, backend: KlassHeroWeb.Gettext

  @type bucket :: :morning | :afternoon | :evening

  @doc """
  Returns the configured app default timezone.

  Single source of truth for "where the app considers itself to be" so a
  future per-user timezone preference can plug in without changing call
  sites.
  """
  @spec default_tz() :: String.t()
  def default_tz do
    Application.get_env(:klass_hero, :default_tz, "Europe/Berlin")
  end

  @doc """
  Buckets a UTC `DateTime` into a time-of-day atom for the given timezone.

  Buckets (in local time):
    * `:morning`   — 05:00–11:59
    * `:afternoon` — 12:00–17:59
    * `:evening`   — 18:00–04:59
  """
  @spec bucket(DateTime.t(), String.t()) :: bucket()
  def bucket(%DateTime{} = utc, tz \\ default_tz()) do
    utc
    |> DateTime.shift_zone!(tz)
    |> Map.fetch!(:hour)
    |> hour_to_bucket()
  end

  defp hour_to_bucket(hour) when hour in 5..11, do: :morning
  defp hour_to_bucket(hour) when hour in 12..17, do: :afternoon
  defp hour_to_bucket(_hour), do: :evening

  @doc """
  Localized greeting copy for a bucket.
  """
  @spec text(bucket()) :: String.t()
  def text(:morning), do: gettext("Good morning")
  def text(:afternoon), do: gettext("Good afternoon")
  def text(:evening), do: gettext("Good evening")

  @doc """
  Extracts the first whitespace-delimited token of `user.name`.

  Returns `nil` for missing/blank names or a `nil` user, so the caller can
  decide whether to drop the name segment of the greeting.
  """
  @spec first_name(struct() | map() | nil) :: String.t() | nil
  def first_name(nil), do: nil
  def first_name(%{name: name}), do: extract_first_name(name)
  def first_name(_), do: nil

  defp extract_first_name(nil), do: nil

  defp extract_first_name(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.split(~r/\s+/, parts: 2)
    |> case do
      [""] -> nil
      [first | _] -> first
    end
  end

  @doc """
  Composes the dashboard title: greeting bucket + optional first name.

  Options:
    * `:user` — anything with a `:name` field; appended as ", Firstname" when present
    * `:tz`   — display timezone (defaults to `default_tz/0`)
  """
  @spec title(DateTime.t(), keyword()) :: String.t()
  def title(%DateTime{} = utc, opts \\ []) do
    tz = Keyword.get(opts, :tz, default_tz())
    user = Keyword.get(opts, :user)

    base = utc |> bucket(tz) |> text()

    case first_name(user) do
      nil -> base
      name -> "#{base}, #{name}"
    end
  end
end
