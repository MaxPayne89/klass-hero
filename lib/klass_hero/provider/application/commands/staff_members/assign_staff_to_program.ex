defmodule KlassHero.Provider.Application.Commands.StaffMembers.AssignStaffToProgram do
  @moduledoc """
  Use case for assigning a staff member to a program.

  Persists the assignment and publishes a domain event so that
  downstream contexts (e.g., Messaging) can react via integration events.

  ## Return values

  - `{:ok, ProgramStaffAssignment.t()}` — assignment created successfully
  - `{:error, :already_assigned}` — the staff member is already assigned to this program
  - `{:error, :not_found}` — the staff member does not exist
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
  Assigns a staff member to a program.

  Expects a map with:
  - `:provider_id` — Required. The provider this assignment belongs to.
  - `:program_id` — Required. The program to assign the staff member to.
  - `:staff_member_id` — Required. The staff member to assign.
  """
  def execute(attrs) when is_map(attrs) do
    with {:ok, staff_member} <- Provider.get_staff_member(attrs.staff_member_id),
         assignment_attrs = Map.put(attrs, :assigned_at, DateTime.utc_now()),
         {:ok, assignment} <- @assignment_repo.create(assignment_attrs) do
      publish_event(assignment, staff_member)

      Logger.info("Staff member assigned to program",
        staff_member_id: assignment.staff_member_id,
        program_id: assignment.program_id
      )

      {:ok, assignment}
    end
  end

  defp publish_event(assignment, staff_member) do
    event = ProviderEvents.staff_assigned_to_program(assignment, staff_member)
    DomainEventBus.dispatch(@context, event)
  end
end
