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

  @behaviour KlassHero.Enrollment.Domain.Ports.ForResolvingProgramSchedule

  use KlassHero.Shared.Tracing

  import Ecto.Query, only: [from: 2]

  alias KlassHero.Repo

  @impl true
  def get_program_start_date(program_id) do
    acl_span source: "enrollment", target: "program_catalog" do
      # Trigger: schemaless query on "programs" table
      # Why: Ecto doesn't know field types without a schema, so we must
      #      cast program_id to :binary_id for the UUID column comparison.
      #      We select a {exists?, start_date} tuple to distinguish
      #      "row not found" from "row found with nil start_date".
      # Outcome: correct parameterized query against the binary_id primary key
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
