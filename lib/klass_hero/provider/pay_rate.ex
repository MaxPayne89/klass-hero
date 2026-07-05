defmodule KlassHero.Provider.PayRate do
  @moduledoc """
  Value object pairing a rate type (`:hourly` | `:per_session`) with a `Money` amount.

  Staff members may have no rate (nil), an hourly rate, or a per-session rate —
  never both. Mutual exclusivity is guaranteed by the type tag: a single `PayRate`
  can only carry one type.

  Persisted flat on `staff_members` as `rate_type`/`rate_amount`/`rate_currency`;
  `KlassHero.Provider.StaffMember` flattens a `%PayRate{}` onto those columns on
  write and rebuilds it (via `from_persistence/1`) into the virtual `:pay_rate`
  field on read.
  """

  alias KlassHero.Shared.Money

  @enforce_keys [:type, :money]
  defstruct [:type, :money]

  @type rate_type :: :hourly | :per_session
  @type t :: %__MODULE__{type: rate_type(), money: Money.t()}

  @valid_types [:hourly, :per_session]

  @doc "Supported rate types."
  @spec valid_types() :: [rate_type()]
  def valid_types, do: @valid_types

  @doc "Smart constructor for an hourly rate."
  @spec hourly(Decimal.t() | integer() | String.t(), atom() | String.t()) ::
          {:ok, t()} | {:error, [String.t()]}
  def hourly(amount, currency \\ :EUR), do: build(:hourly, amount, currency)

  @doc "Smart constructor for a per-session rate."
  @spec per_session(Decimal.t() | integer() | String.t(), atom() | String.t()) ::
          {:ok, t()} | {:error, [String.t()]}
  def per_session(amount, currency \\ :EUR), do: build(:per_session, amount, currency)

  @doc """
  Raw constructor. Validates that `type` is supported and `money` is a valid `%Money{}`.
  Use the smart constructors (`hourly/2`, `per_session/2`) at call sites when possible.
  """
  @spec new(%{type: rate_type(), money: Money.t() | nil}) ::
          {:ok, t()} | {:error, [String.t()]}
  def new(%{type: type, money: money}) do
    with :ok <- validate_type(type),
         :ok <- validate_money(money) do
      {:ok, %__MODULE__{type: type, money: money}}
    end
  end

  @doc """
  Reconstructs a PayRate from persisted parts without revalidating.
  The caller (schema loader) has already reconstructed the Money value object.
  """
  @spec from_persistence(%{type: rate_type() | String.t(), money: Money.t()}) ::
          {:ok, t()} | {:error, :invalid_persistence_data}
  def from_persistence(%{type: type, money: %Money{} = money}) when type in @valid_types do
    {:ok, %__MODULE__{type: type, money: money}}
  end

  def from_persistence(%{type: type, money: %Money{} = money}) when is_binary(type) do
    from_persistence(%{type: String.to_existing_atom(type), money: money})
  rescue
    ArgumentError -> {:error, :invalid_persistence_data}
  end

  def from_persistence(_), do: {:error, :invalid_persistence_data}

  @doc "Predicate — true when the struct passes all validations."
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{type: type, money: %Money{}}) when type in @valid_types, do: true
  def valid?(_), do: false

  defp build(type, amount, currency) do
    with {:ok, money} <- Money.new(amount, currency) do
      {:ok, %__MODULE__{type: type, money: money}}
    end
  end

  defp validate_type(type) when type in @valid_types, do: :ok

  defp validate_type(_), do: {:error, ["type must be one of #{inspect(@valid_types)}"]}

  defp validate_money(%Money{}), do: :ok
  defp validate_money(_), do: {:error, ["money must be a valid %Money{} struct"]}
end
