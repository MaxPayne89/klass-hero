defmodule KlassHeroWeb.Admin.Filters.ConsentStatusFilter do
  @moduledoc false

  use Backpex.Filters.Select

  import Ecto.Query

  alias Backpex.Filters.Select

  @impl Backpex.Filter
  def label, do: "Status"

  @impl Select
  def prompt, do: "All statuses..."

  @impl Select
  def options(_assigns) do
    [
      {"Active", "active"},
      {"Withdrawn", "withdrawn"}
    ]
  end

  # Status is derived from withdrawn_at nullability, not a stored column value.
  @impl Backpex.Filter
  def query(query, _attribute, "active", _assigns) do
    where(query, [x], is_nil(x.withdrawn_at))
  end

  @impl Backpex.Filter
  def query(query, _attribute, "withdrawn", _assigns) do
    where(query, [x], not is_nil(x.withdrawn_at))
  end

  @impl Backpex.Filter
  def query(query, _attribute, _value, _assigns), do: query
end
