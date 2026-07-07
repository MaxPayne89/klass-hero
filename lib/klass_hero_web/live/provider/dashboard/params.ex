defmodule KlassHeroWeb.Provider.Dashboard.Params do
  @moduledoc """
  Pure parsers and coercions shared by the provider-dashboard sub-LiveViews.

  Extracted verbatim from the former `DashboardLive` god-module so the program,
  staff, and profile forms can share one set of input coercions with zero socket
  coupling. Every function here is total — malformed input returns `nil`/`[]`
  rather than raising, because these run against raw form params.
  """

  @doc "Coerce a form value to a `Decimal`, or `nil` when blank/unparseable."
  def parse_decimal(nil), do: nil
  def parse_decimal(""), do: nil
  def parse_decimal(%Decimal{} = d), do: d

  def parse_decimal(value) when is_binary(value) do
    value
    |> String.trim()
    |> Decimal.parse()
    |> case do
      {decimal, ""} -> decimal
      _other -> nil
    end
  end

  @doc "Coerce a form value to a positive integer, or `nil` when blank/invalid/non-positive."
  def parse_integer(nil), do: nil
  def parse_integer(""), do: nil

  def parse_integer(val) when is_binary(val) do
    case Integer.parse(val) do
      {int, ""} when int >= 1 -> int
      _ -> nil
    end
  end

  def parse_integer(val) when is_integer(val), do: val

  @doc "Parse an ISO8601 date string, or `nil` when blank/malformed."
  def parse_date(nil), do: nil
  def parse_date(""), do: nil

  def parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  @doc "Parse a `HH:MM` or `HH:MM:SS` time string, or `nil` when blank/malformed."
  def parse_time(nil), do: nil
  def parse_time(""), do: nil

  def parse_time(value) when is_binary(value) do
    # Try parsing as-is first (handles "HH:MM:SS" from re-rendered %Time{} structs),
    # then fall back to appending ":00" (handles "HH:MM" from HTML time inputs)
    case Time.from_iso8601(value) do
      {:ok, time} ->
        time

      {:error, _} ->
        case Time.from_iso8601(value <> ":00") do
          {:ok, time} -> time
          {:error, _} -> nil
        end
    end
  end

  @doc "Reject blank entries from a list of selected meeting days; `[]` for nil/non-list input."
  def parse_meeting_days(nil), do: []
  def parse_meeting_days(days) when is_list(days), do: Enum.reject(days, &(&1 == ""))
  def parse_meeting_days(_), do: []

  @doc "Return the value unless it is blank (`\"\"`/`nil`), in which case `nil`."
  def presence(""), do: nil
  def presence(nil), do: nil
  def presence(value), do: value

  @doc "Apply `fun` to `value`, short-circuiting to `nil` when `value` is nil."
  def nil_safe(nil, _fun), do: nil
  def nil_safe(value, fun), do: fun.(value)

  @doc "Drop `:eligibility_at` from attrs when it is nil; leave attrs untouched otherwise."
  def drop_nil_eligibility_at(%{eligibility_at: nil} = attrs), do: Map.delete(attrs, :eligibility_at)
  def drop_nil_eligibility_at(attrs), do: attrs
end
