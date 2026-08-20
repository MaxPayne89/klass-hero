defmodule KlassHero.Provider.Domain.ReadModels.StaffProgramAccess do
  @moduledoc """
  Which Programs a Staff Member may see and act on.

  Derived from live **Program Staff Assignments** — the rows a provider creates
  deliberately, which already decide conversation membership, session-detail
  attribution and the offboarding teardown — narrowed by whether each of those
  programs is still open. Assignment says *who*; closure says *whether it still
  counts* (#1082). Never from `staff_members.tags`, which are descriptive
  **Specialties** and carry no access (#1323).

  Both inputs are write-model facts, read strongly-consistently. Closure is asked
  of `programs` through `ProgramCatalog.split_programs_by_closure/2`, never of the
  `program_listings` projection: projection lag revoking access is the failure
  `KlassHeroWeb.Helpers.StaffLiveHelpers`'s moduledoc warns about, and it applies
  to closure exactly as it does to assignment.

  That same read carries the **tenancy**, so consumers do not re-check the
  provider — a filter each caller must remember is a filter one of them eventually
  omits.

  The two sets are therefore **not** exhaustive over the assignment rows, and that
  is deliberate. An assignment naming another provider's program, or one since
  deleted, appears in neither: it grants nothing *and* is not listed back to the
  staff member. Deriving `closed_program_ids` as "assigned minus open" would have
  put a foreign program in the dashboard's "Completed" section — fail-closed is
  the right instinct for a gate, but this set is also rendered.

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

  @typedoc """
  The Programs one Staff Member may see, split by whether each is still open.

  Disjoint, but **not** exhaustive over their assignment rows: an assignment naming
  a program that belongs to another provider, or one since deleted, is in neither
  set. Do not "restore" exhaustiveness — putting the unresolvable ones in
  `closed_program_ids` lists them back to the staff member, because that set is
  rendered as their Completed programs.
  """
  @type t :: %__MODULE__{
          staff_member_id: String.t(),
          program_ids: MapSet.t(String.t()),
          closed_program_ids: MapSet.t(String.t())
        }

  @enforce_keys [:staff_member_id, :program_ids, :closed_program_ids]

  defstruct [:staff_member_id, :program_ids, :closed_program_ids]

  @doc """
  Whether the staff member may see and act on `program_id`.

  A staff member with no assignments is authorized for nothing — including the
  case where they have only just been hired. That is the correct answer, not a
  degenerate one: assignment is a deliberate act, so "not assigned yet" and "not
  allowed" are the same fact.

  Says nothing about *why* a program is refused. A caller that needs to tell a
  Closed Program apart from one that was never assigned asks `closed?/2`.
  """
  @spec authorized?(t(), String.t()) :: boolean()
  def authorized?(%__MODULE__{program_ids: program_ids}, program_id) do
    MapSet.member?(program_ids, program_id)
  end

  @doc """
  Whether `program_id` is assigned to this staff member but **Closed** — so it
  may be named and listed, but not acted on (#1082).

  This is the read-only half of the roster: the dashboard's "Completed" section
  is built from it, and it is what lets a refusal say "this program has closed"
  rather than "you are not assigned".
  """
  @spec closed?(t(), String.t()) :: boolean()
  def closed?(%__MODULE__{closed_program_ids: closed_program_ids}, program_id) do
    MapSet.member?(closed_program_ids, program_id)
  end
end
