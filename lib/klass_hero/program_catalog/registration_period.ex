defmodule KlassHero.ProgramCatalog.RegistrationPeriod do
  @moduledoc """
  Value object representing a program's registration window.

  Encapsulates the start and end dates during which parents may enroll. Both
  dates are optional — when both are nil, registration is always open. Assembled
  from the `registration_start_date` / `registration_end_date` columns on the
  `programs` table and exposed as `program.registration_period`.

  Date ordering is validated by the `Program` changeset (the single gatekeeper);
  this struct only interprets the window.
  """

  defstruct [:start_date, :end_date]

  @type t :: %__MODULE__{
          start_date: Date.t() | nil,
          end_date: Date.t() | nil
        }

  @type status :: :always_open | :upcoming | :open | :closed

  @doc "The current status of the registration window relative to today."
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

  @doc "Whether registration is currently open."
  @spec open?(t()) :: boolean()
  def open?(%__MODULE__{} = rp), do: status(rp) in [:always_open, :open]
end
