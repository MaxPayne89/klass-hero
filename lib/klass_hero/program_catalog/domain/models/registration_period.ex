defmodule KlassHero.ProgramCatalog.Domain.Models.RegistrationPeriod do
  @moduledoc """
  Value object representing a program's registration window.

  Encapsulates the start and end dates during which parents may enroll.
  Both dates are optional — when both are nil, registration is always open.
  """

  defstruct [:start_date, :end_date]

  @type t :: %__MODULE__{
          start_date: Date.t() | nil,
          end_date: Date.t() | nil
        }

  @type status :: :always_open | :upcoming | :open | :closed

  @spec new(map()) :: {:ok, t()} | {:error, [String.t()]}
  def new(attrs) when is_map(attrs) do
    start_date = attrs[:start_date]
    end_date = attrs[:end_date]

    errors = validate_date_ordering(start_date, end_date)

    if errors == [] do
      {:ok, %__MODULE__{start_date: start_date, end_date: end_date}}
    else
      {:error, errors}
    end
  end

  @spec status(t()) :: status()
  def status(%__MODULE__{start_date: nil, end_date: nil}), do: :always_open

  def status(%__MODULE__{start_date: start_date, end_date: nil}) do
    if Date.before?(Date.utc_today(), start_date), do: :upcoming, else: :open
  end

  def status(%__MODULE__{start_date: nil, end_date: end_date}) do
    if Date.after?(Date.utc_today(), end_date), do: :closed, else: :open
  end

  def status(%__MODULE__{start_date: start_date, end_date: end_date}) do
    today = Date.utc_today()

    cond do
      Date.before?(today, start_date) -> :upcoming
      Date.after?(today, end_date) -> :closed
      true -> :open
    end
  end

  @spec open?(t()) :: boolean()
  def open?(%__MODULE__{} = rp), do: status(rp) in [:always_open, :open]

  defp validate_date_ordering(nil, _), do: []
  defp validate_date_ordering(_, nil), do: []

  defp validate_date_ordering(%Date{} = start_date, %Date{} = end_date) do
    if Date.before?(start_date, end_date) do
      []
    else
      ["registration_start_date must be before registration_end_date"]
    end
  end
end
