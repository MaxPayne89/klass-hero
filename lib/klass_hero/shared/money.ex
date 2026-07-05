defmodule KlassHero.Shared.Money do
  @moduledoc """
  Immutable value object representing a monetary amount in a specific currency.

  Used for any domain value that has an amount and currency — e.g. staff pay rates.
  Existing codebase fields that store bare `Decimal.t()` (program prices, enrollment fees)
  may migrate to this type over time.
  """

  @enforce_keys [:amount, :currency]
  defstruct [:amount, :currency]

  @type t :: %__MODULE__{amount: Decimal.t(), currency: atom()}

  @valid_currencies ~w(EUR)a

  @doc "Supported currency atoms. Extend carefully — expansion may require locale/formatting work."
  @spec valid_currencies() :: [atom()]
  def valid_currencies, do: @valid_currencies

  @doc """
  Builds a Money value with validation.

  Accepts amount as `Decimal.t()`, integer, or parseable string.
  Returns `{:ok, money}` on success, `{:error, [reasons]}` on failure.
  """
  @spec new(Decimal.t() | integer() | String.t() | nil, atom() | String.t()) ::
          {:ok, t()} | {:error, [String.t()]}
  def new(amount, currency \\ :EUR) do
    with {:ok, decimal} <- coerce_amount(amount),
         :ok <- validate_non_negative(decimal),
         {:ok, currency_atom} <- coerce_currency(currency) do
      {:ok, %__MODULE__{amount: decimal, currency: currency_atom}}
    end
  end

  @doc """
  Reconstructs Money from persisted data without revalidating.

  Storage stores currency as a string; this converts it back to the atom.
  Uses `String.to_existing_atom/1` — safe because all valid currencies are
  declared at compile time by `@valid_currencies` above.
  """
  @spec from_persistence(%{amount: Decimal.t(), currency: String.t() | atom()}) ::
          {:ok, t()} | {:error, :invalid_persistence_data}
  def from_persistence(%{amount: %Decimal{} = amount, currency: currency})
      when is_binary(currency) or is_atom(currency) do
    {:ok, %__MODULE__{amount: amount, currency: atomize_currency(currency)}}
  rescue
    ArgumentError -> {:error, :invalid_persistence_data}
  end

  def from_persistence(_), do: {:error, :invalid_persistence_data}

  @doc "Structural equality — same amount (via Decimal.equal?/2) and same currency atom."
  @spec equal?(t(), t()) :: boolean()
  def equal?(%__MODULE__{amount: a1, currency: c1}, %__MODULE__{amount: a2, currency: c2}) do
    c1 == c2 and Decimal.equal?(a1, a2)
  end

  @doc """
  Formats a Money value for display with the currency symbol, e.g. `"€25.00"`.

  Rounds to 2 decimal places.
  """
  @spec format(t()) :: String.t()
  def format(%__MODULE__{amount: amount, currency: currency}) do
    "#{symbol(currency)}#{amount |> Decimal.round(2) |> Decimal.to_string()}"
  end

  defp symbol(:EUR), do: "€"

  defp coerce_amount(nil), do: {:error, ["amount is required"]}

  defp coerce_amount(%Decimal{} = d), do: {:ok, d}

  defp coerce_amount(n) when is_integer(n), do: {:ok, Decimal.new(n)}

  defp coerce_amount(s) when is_binary(s) do
    case Decimal.parse(s) do
      {decimal, ""} -> {:ok, decimal}
      _ -> {:error, ["amount is not a valid number"]}
    end
  end

  defp coerce_amount(_), do: {:error, ["amount must be a Decimal, integer, or string"]}

  defp validate_non_negative(%Decimal{} = d) do
    if Decimal.compare(d, Decimal.new(0)) == :lt,
      do: {:error, ["amount cannot be negative"]},
      else: :ok
  end

  defp coerce_currency(currency) when currency in @valid_currencies, do: {:ok, currency}

  defp coerce_currency(currency) when is_binary(currency) do
    case Enum.find(@valid_currencies, &(Atom.to_string(&1) == currency)) do
      nil -> invalid_currency_error()
      atom -> {:ok, atom}
    end
  end

  defp coerce_currency(_), do: invalid_currency_error()

  defp invalid_currency_error, do: {:error, ["currency must be one of #{inspect(@valid_currencies)}"]}

  defp atomize_currency(c) when is_atom(c), do: c
  defp atomize_currency(c) when is_binary(c), do: String.to_existing_atom(c)
end
