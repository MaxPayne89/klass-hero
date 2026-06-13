defmodule KlassHero.Participation.Adapters.Driven.ACL.EnrolledChildrenResolver do
  @moduledoc """
  ACL adapter resolving enrolled child IDs from the Enrollment context.

  Extracts only `child_id` values; all other enrollment data is discarded at the ACL boundary.
  """

  @behaviour KlassHero.Participation.Domain.Ports.ForResolvingEnrolledChildren

  alias KlassHero.Enrollment

  # Uses the enriched roster endpoint (slight over-fetch) to avoid adding a new function
  # to the Enrollment context. Acceptable for class-sized lists.
  @impl true
  def list_enrolled_child_ids(program_id) when is_binary(program_id) do
    program_id
    |> Enrollment.list_program_enrollments()
    |> Enum.map(& &1.child_id)
    # Defensive: DB unique partial index prevents duplicate active enrollments per child/program,
    # but dedup here guards against any future loosening of that constraint
    |> Enum.uniq()
  end
end
