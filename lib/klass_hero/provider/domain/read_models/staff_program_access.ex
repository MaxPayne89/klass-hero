defmodule KlassHero.Provider.Domain.ReadModels.StaffProgramAccess do
  @moduledoc """
  Which Programs a Staff Member may see and act on.

  Derived from live **Program Staff Assignments** — the rows a provider creates
  deliberately, which already decide conversation membership, session-detail
  attribution and the offboarding teardown. Never from `staff_members.tags`,
  which are descriptive **Specialties** and carry no access (#1323).

  Until #1323 the four staff surfaces derived this by matching a staff member's
  tags against `program.category`, with an empty tag list silently meaning *every*
  program. That made an editorial field into an authorization rule: whether you
  could check a child in and out of a session depended on a category string
  nobody thought of as a permission. This struct is the single answer instead,
  and `Assignments.get_staff_program_access/1` is the only thing that builds it.

  The counterpart from the program's side is
  `KlassHero.Provider.Domain.ReadModels.ProgramStaffing` — same rows, asked the
  other way round.

  `program_ids` is a `MapSet` because callers gate per row while rendering a
  stream; `authorized?/2` is the only way to ask, so no caller re-derives the
  membership test.
  """

  @typedoc "Every Program one Staff Member is currently assigned to."
  @type t :: %__MODULE__{
          staff_member_id: String.t(),
          program_ids: MapSet.t(String.t())
        }

  @enforce_keys [:staff_member_id, :program_ids]

  defstruct [:staff_member_id, :program_ids]

  @doc """
  Whether the staff member may see and act on `program_id`.

  A staff member with no assignments is authorized for nothing — including the
  case where they have only just been hired. That is the correct answer, not a
  degenerate one: assignment is a deliberate act, so "not assigned yet" and "not
  allowed" are the same fact.
  """
  @spec authorized?(t(), String.t()) :: boolean()
  def authorized?(%__MODULE__{program_ids: program_ids}, program_id) do
    MapSet.member?(program_ids, program_id)
  end
end
