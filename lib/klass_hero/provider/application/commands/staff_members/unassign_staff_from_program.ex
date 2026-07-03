defmodule KlassHero.Provider.Application.Commands.StaffMembers.UnassignStaffFromProgram do
  @moduledoc """
  Use case for unassigning a staff member from a program.

  Soft-deletes the active assignment record and publishes a domain event so that
  downstream contexts (e.g., Messaging) can react via integration events.

  ## Return values

  - `{:ok, ProgramStaffAssignment.t()}` — unassignment recorded successfully
  - `{:error, :not_found}` — no active assignment exists for this program/staff pair
  """

  alias KlassHero.Provider
  alias KlassHero.Provider.Domain.Events.ProviderEvents
  alias KlassHero.Shared.DomainEventBus

  require Logger

  @context KlassHero.Provider
  @assignment_repo Application.compile_env!(:klass_hero, [
                     :provider,
                     :for_storing_program_staff_assignments
                   ])

  @doc """
  Unassigns a staff member from a program.

  - `program_id` — The program to unassign the staff member from.
  - `staff_member_id` — The staff member to unassign.
  """
  def execute(program_id, staff_member_id) when is_binary(program_id) and is_binary(staff_member_id) do
    with {:ok, staff_member} <- Provider.get_staff_member(staff_member_id),
         {:ok, assignment} <- @assignment_repo.unassign(program_id, staff_member_id) do
      publish_event(assignment, staff_member)

      Logger.info("Staff member unassigned from program",
        staff_member_id: staff_member_id,
        program_id: program_id
      )

      {:ok, assignment}
    end
  end

  defp publish_event(assignment, staff_member) do
    event = ProviderEvents.staff_unassigned_from_program(assignment, staff_member)
    DomainEventBus.dispatch(@context, event)
  end
end
