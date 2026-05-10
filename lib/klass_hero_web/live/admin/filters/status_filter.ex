defmodule KlassHeroWeb.Admin.Filters.StatusFilter do
  @moduledoc false

  use Backpex.Filters.Boolean

  import Ecto.Query

  alias Backpex.Filters.Boolean

  @impl Backpex.Filter
  def label, do: "Booking Status"

  @impl Boolean
  def options(_assigns) do
    [
      %{label: "Pending", key: "pending", predicate: dynamic([x], x.status == :pending)},
      %{label: "Confirmed", key: "confirmed", predicate: dynamic([x], x.status == :confirmed)},
      %{label: "Completed", key: "completed", predicate: dynamic([x], x.status == :completed)},
      %{label: "Cancelled", key: "cancelled", predicate: dynamic([x], x.status == :cancelled)}
    ]
  end
end
