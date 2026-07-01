defmodule KlassHero.Enrollment.Adapters.Driven.ACL.ProgramScheduleACL do
  @moduledoc """
  ACL adapter that resolves program start dates for eligibility checks.

  The Enrollment context needs to know when a program starts for
  "at program start" eligibility checks (e.g., age at program start).

  ## Why direct DB query instead of ProgramCatalog facade?

  ProgramCatalog already depends on Enrollment (for capacity ACL).
  Adding Enrollment → ProgramCatalog would create a dependency cycle.
  This adapter queries the `programs` table directly — acceptable in
  the adapter layer since it's infrastructure, not domain logic.
  """

  use KlassHero.Shared.Tracing

  import Ecto.Query, only: [from: 2]

  alias KlassHero.Repo

  def get_program_start_date(program_id) do
    acl_span source: "enrollment", target: "program_catalog" do
      # Schemaless query: explicit :binary_id cast required (Ecto can't infer types without a schema).
      # The {true, start_date} tuple distinguishes "not found" from "found with nil start_date".
      query =
        from(p in "programs",
          where: p.id == type(^program_id, :binary_id),
          select: {true, p.start_date}
        )

      case Repo.one(query) do
        {true, start_date} -> {:ok, start_date}
        nil -> {:error, :not_found}
      end
    end
  end
end
