defmodule KlassHero.Enrollment.Adapters.Driven.ACL.ProgramCatalogACL do
  @moduledoc """
  ACL adapter that resolves program titles for a provider.

  The Enrollment context needs program title->ID mappings for CSV import.

  ## Why direct DB query instead of ProgramCatalog facade?

  ProgramCatalog already depends on Enrollment (for capacity ACL).
  Adding Enrollment -> ProgramCatalog would create a dependency cycle.
  This adapter queries the `programs` table directly — acceptable in
  the adapter layer since it's infrastructure, not domain logic.
  """

  use KlassHero.Shared.Tracing

  import Ecto.Query, only: [from: 2]

  alias KlassHero.Repo

  def list_program_titles_for_provider(provider_id) when is_binary(provider_id) do
    acl_span source: "enrollment", target: "program_catalog" do
      # Guard: type(^provider_id, :binary_id) raises Ecto.Query.CastError on invalid format;
      # an invalid UUID returns an empty map and build_context handles the empty-map case.
      case Ecto.UUID.cast(provider_id) do
        {:ok, _} ->
          from(p in "programs",
            where: p.provider_id == type(^provider_id, :binary_id),
            select: {p.title, type(p.id, :binary_id)}
          )
          |> Repo.all()
          |> Map.new()

        :error ->
          %{}
      end
    end
  end

  def program_owned_by?(program_id, provider_id) when is_binary(program_id) and is_binary(provider_id) do
    acl_span source: "enrollment", target: "program_catalog" do
      with {:ok, _} <- Ecto.UUID.cast(program_id),
           {:ok, _} <- Ecto.UUID.cast(provider_id) do
        from(p in "programs",
          where:
            p.id == type(^program_id, :binary_id) and
              p.provider_id == type(^provider_id, :binary_id),
          select: 1
        )
        |> Repo.one()
        |> case do
          nil -> false
          1 -> true
        end
      else
        :error -> false
      end
    end
  end
end
