defmodule KlassHero.Provider.OffboardStaffMember do
  @moduledoc """
  Ends a staff member's employment **and** takes them off every program (#1292).

  The sibling of `Provider.Staff.deactivate_staff_member/1`, and deliberately not
  the same operation:

    * **Deactivation** pauses the employment link. Program Staff Assignments
      survive on purpose, because unassigning would strip Messaging conversation
      membership that reactivation cannot give back.
    * **Offboarding** is the provider saying the person no longer works here. The
      assignments have to go, and going through the assignment rows is what
      stages `staff_unassigned_from_program` — the event Messaging listens to in
      order to soft-leave the person from the program's conversations. (Whether
      Messaging still *counts* them as staff needs no event since #1321; it is
      derived from these same rows, so it flips with this write.)

  It replaces a bare `Repo.delete` whose assignments were destroyed by an
  `on_delete: :delete_all` FK: Postgres removed the rows, no changeset ran, and
  so nothing was ever staged. The removed staff member stayed a conversation
  participant indefinitely.

  Lives at the context root rather than in `staff.ex` because it spans two
  entities under one transaction — the same reason `AnonymizeUserData` does.

  Ordering is load-bearing: the assignments are retired **before** the employment
  write, so the `active` flip cannot short-circuit the teardown on a re-run.
  """

  use KlassHero.Shared.Tracing

  alias KlassHero.Provider.Assignments
  alias KlassHero.Provider.Domain.Events.ProviderEvents
  alias KlassHero.Provider.ProgramStaffAssignment
  alias KlassHero.Provider.StaffMember
  alias KlassHero.Repo
  alias KlassHero.Shared.Outbox

  @context KlassHero.Provider

  @doc """
  Offboards a staff member, in one transaction.

  Retires every live Program Staff Assignment (staging one
  `staff_unassigned_from_program` per program), then ends the employment link and
  stages `staff_member_deactivated`. All of it commits together, and the outbox
  turns the batch into a single ordered delivery job.

  Takes the struct, so provider-initiated callers scope through
  `Provider.get_staff_member/2` first — foreign ≡ missing is that function's
  guarantee, and re-deriving it here would give the guard a second home.

  Idempotent: an already-offboarded member with no live assignments comes back
  with `unassigned_count: 0` and nothing staged.
  """
  @spec execute(StaffMember.t()) ::
          {:ok, %{staff_member: StaffMember.t(), unassigned_count: non_neg_integer()}}
          | {:error, term()}
  def execute(%StaffMember{} = staff) do
    context_span entity: "staff_member" do
      Outbox.transact(@context, fn -> offboard(staff) end)
    end
  end

  defp offboard(staff) do
    with {:ok, unassigned, unassignment_events} <- retire_assignments(staff),
         {:ok, ended, employment_events} <- end_employment(staff) do
      result = %{staff_member: ended, unassigned_count: length(unassigned)}

      {:ok, result, unassignment_events ++ employment_events}
    end
  end

  # `unassign_changeset/1` clears `is_lead_instructor` as it retires the row, so
  # leading a program is not an obstacle here. The public
  # `Assignments.unassign_staff_from_program/3` is deliberately not reused: it
  # refuses to retire a lead (a rail on the interactive one-program detach), and
  # it would open its own transaction per program — N delivery jobs instead of one.
  defp retire_assignments(%StaffMember{} = staff) do
    staff.id
    |> Assignments.list_active_assignments_for_staff_member()
    |> Enum.reduce_while({:ok, [], []}, fn assignment, {:ok, retired, events} ->
      case Repo.update(ProgramStaffAssignment.unassign_changeset(assignment)) do
        {:ok, unassigned} ->
          event = ProviderEvents.staff_unassigned_from_program(unassigned, staff)
          {:cont, {:ok, [unassigned | retired], [event | events]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, retired, events} -> {:ok, Enum.reverse(retired), Enum.reverse(events)}
      {:error, reason} -> {:error, reason}
    end
  end

  # Already inactive: the employment link is where it should be, and re-staging
  # `staff_member_deactivated` would announce a change that did not happen.
  defp end_employment(%StaffMember{active: false} = staff), do: {:ok, staff, []}

  defp end_employment(%StaffMember{} = staff) do
    with {:ok, ended} <- Repo.update(StaffMember.deactivate_changeset(staff)) do
      {:ok, ended, [ProviderEvents.staff_member_deactivated(ended)]}
    end
  end
end
