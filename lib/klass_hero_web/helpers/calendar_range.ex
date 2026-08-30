defmodule KlassHeroWeb.Helpers.CalendarRange do
  @moduledoc """
  The date arithmetic behind the provider Schedule calendar.

  Pure, so the grid can be tested without a socket, and so `ScheduleLive` is left
  holding only the parts that need one.

  ## One range, for both the query and the grid

  `range_for/2` answers "which days does this view cover" once, and both the
  fetch and the render use that answer. A month view is therefore padded out to
  whole weeks — the grid has to be a rectangle, and if the query covered only
  the calendar month, the leading and trailing cells would be drawn but could
  never show a session that exists on those days.

  ## Weeks start Monday

  `Date.beginning_of_week/2` defaults to Monday for the ISO calendar, which is
  what a German-market product wants. Nothing here passes a start day, so
  changing that default is a one-argument change rather than a sweep.

  ## Stepping clamps

  `step(:month, ~D[2026-01-31], 1)` is 28 February, not 3 March. `Date.shift/2`
  does the clamping; `Date.add/2` would not, and stepping off a 31st would then
  skip a month entirely. The view modes are already `Date.shift/2`'s own unit
  keys, so one clause covers all three.
  """

  @type view_mode :: :day | :week | :month

  @doc """
  The days a view covers — the query range and the grid range, which are the same.
  """
  @spec range_for(view_mode(), Date.t()) :: Date.Range.t()
  def range_for(:day, %Date{} = date), do: Date.range(date, date)

  def range_for(:week, %Date{} = date) do
    Date.range(Date.beginning_of_week(date), Date.end_of_week(date))
  end

  def range_for(:month, %Date{} = date) do
    date
    |> Date.beginning_of_month()
    |> Date.beginning_of_week()
    |> Date.range(date |> Date.end_of_month() |> Date.end_of_week())
  end

  @doc """
  Moves the focus date one whole period forward (`1`) or back (`-1`).
  """
  @spec step(view_mode(), Date.t(), -1 | 1) :: Date.t()
  def step(mode, %Date{} = date, direction) when mode in [:day, :week, :month] and direction in [-1, 1] do
    Date.shift(date, [{mode, direction}])
  end
end
