defmodule KlassHero.Admin.Queries do
  @moduledoc """
  Cross-context read-only queries for admin dashboard dropdowns.

  Returns plain maps for select/dropdown options. No domain logic.
  Located in the data layer because it executes Ecto/Repo queries directly.

  Admin owns no tables, so every read here is cross-context by construction — which is
  the point of the module, not a smell. Each still carries an `acl_span` so the hops
  show up in traces like any other; `mix lint_acl_boundary` enforces it.
  """

  use KlassHero.Shared.Tracing

  import Ecto.Query

  alias KlassHero.Repo

  @doc """
  Returns all providers as `%{id: uuid, label: business_name}` maps,
  sorted alphabetically by business name.
  """
  def list_providers_for_select do
    acl_span source: "admin", target: "provider" do
      from(p in "providers",
        select: %{id: type(p.id, :binary_id), label: p.business_name},
        order_by: [asc: p.business_name]
      )
      |> Repo.all()
    end
  end

  @doc """
  Returns all programs as `%{id: uuid, label: title, provider_id: uuid}` maps,
  sorted alphabetically by title.

  Includes `provider_id` so the parent LiveView can filter programs in-memory
  when a provider is selected (cascading dropdown).
  """
  def list_programs_for_select do
    acl_span source: "admin", target: "program_catalog" do
      from(p in "programs",
        select: %{
          id: type(p.id, :binary_id),
          label: p.title,
          provider_id: type(p.provider_id, :binary_id)
        },
        order_by: [asc: p.title]
      )
      |> Repo.all()
    end
  end
end
