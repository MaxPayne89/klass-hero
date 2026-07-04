defmodule KlassHero.Provider.Assignments do
  @moduledoc """
  Program ↔ staff assignment commands and queries for the Provider context.

  Assignment writes emit domain events on the Provider bus (promoted to durable
  integration events); reads expose active assignments and the staff behind them.
  Reached through `KlassHero.Provider`'s public API.
  """

  use KlassHero.Shared.Tracing

  import Ecto.Query, warn: false

  alias KlassHero.Provider
  alias KlassHero.Provider.Domain.Events.ProviderEvents
  alias KlassHero.Provider.ProgramStaffAssignment
  alias KlassHero.Provider.StaffMember
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.EctoErrorHelpers
  alias KlassHero.Shared.DomainEventBus

  require Logger

  @doc """
  Assigns a staff member to a program.

  Returns:
  - `{:ok, ProgramStaffAssignment.t()}` on success
  - `{:error, :already_assigned}` if the staff member is already assigned
  - `{:error, :not_found}` if staff member does not exist
  """
  @spec assign_staff_to_program(map()) ::
          {:ok, ProgramStaffAssignment.t()}
          | {:error, :already_assigned | :not_found | term()}
  def assign_staff_to_program(attrs) when is_map(attrs) do
    context_span entity: "program_staff_assignment" do
      with {:ok, staff_member} <- Provider.get_staff_member(attrs.staff_member_id),
           assignment_attrs = Map.put(attrs, :assigned_at, DateTime.utc_now()),
           {:ok, assignment} <- insert_program_staff_assignment(assignment_attrs) do
        assignment
        |> ProviderEvents.staff_assigned_to_program(staff_member)
        |> dispatch_assignment_event()

        Logger.info("Staff member assigned to program",
          staff_member_id: assignment.staff_member_id,
          program_id: assignment.program_id
        )

        {:ok, assignment}
      end
    end
  end

  @doc """
  Unassigns a staff member from a program.

  Returns:
  - `{:ok, ProgramStaffAssignment.t()}` on success
  - `{:error, :not_found}` if no active assignment exists
  """
  @spec unassign_staff_from_program(String.t(), String.t()) ::
          {:ok, ProgramStaffAssignment.t()} | {:error, :not_found | term()}
  def unassign_staff_from_program(program_id, staff_member_id)
      when is_binary(program_id) and is_binary(staff_member_id) do
    context_span entity: "program_staff_assignment" do
      with {:ok, staff_member} <- Provider.get_staff_member(staff_member_id),
           {:ok, assignment} <- unassign_program_staff_assignment(program_id, staff_member_id) do
        assignment
        |> ProviderEvents.staff_unassigned_from_program(staff_member)
        |> dispatch_assignment_event()

        Logger.info("Staff member unassigned from program",
          staff_member_id: staff_member_id,
          program_id: program_id
        )

        {:ok, assignment}
      end
    end
  end

  @doc """
  Filters a list of programs to only those assigned to a staff member.

  If the staff member has no tags, returns all programs unchanged.
  If tags are set, returns only programs whose category matches a tag.

  The caller is responsible for fetching the programs list (typically
  from `ProgramCatalog.list_programs_for_provider/1`), keeping the
  Provider context free of cross-context dependencies.
  """
  @spec list_assigned_programs(StaffMember.t(), [map()]) :: [map()]
  def list_assigned_programs(%StaffMember{} = staff_member, programs) when is_list(programs) do
    filter_programs_by_tags(programs, staff_member.tags)
  end

  @doc "Lists all active staff assignments for a program."
  @spec list_active_assignments_for_program(String.t()) :: [ProgramStaffAssignment.t()]
  def list_active_assignments_for_program(program_id) when is_binary(program_id) do
    active_assignments_query()
    |> where([a], a.program_id == ^program_id)
    |> Repo.all()
  end

  @doc """
  Lists active staff members assigned to a program.

  Uses a JOIN through `program_staff_assignments` so staff details arrive in a
  single round-trip, ordered by when each assignment was created.
  """
  @spec list_active_staff_for_program(String.t()) :: [StaffMember.t()]
  def list_active_staff_for_program(program_id) when is_binary(program_id) do
    from(s in StaffMember,
      join: a in ProgramStaffAssignment,
      on: a.staff_member_id == s.id and a.provider_id == s.provider_id,
      where: a.program_id == ^program_id and is_nil(a.unassigned_at) and s.active == true,
      order_by: [asc: a.assigned_at],
      select: s
    )
    |> Repo.all()
    |> Enum.map(&StaffMember.load_pay_rate/1)
  end

  @doc "Lists all active staff assignments for a provider."
  @spec list_active_assignments_for_provider(String.t()) :: [ProgramStaffAssignment.t()]
  def list_active_assignments_for_provider(provider_id) when is_binary(provider_id) do
    active_assignments_query()
    |> where([a], a.provider_id == ^provider_id)
    |> Repo.all()
  end

  @doc "Lists all active program assignments for a staff member."
  @spec list_active_assignments_for_staff_member(String.t()) :: [ProgramStaffAssignment.t()]
  def list_active_assignments_for_staff_member(staff_member_id) when is_binary(staff_member_id) do
    active_assignments_query()
    |> where([a], a.staff_member_id == ^staff_member_id)
    |> Repo.all()
  end

  # Dispatches the domain event on the Provider bus. PromoteIntegrationEvents
  # then promotes it to a :critical integration event delivered belt-and-suspenders
  # (PubSub + durable Oban via the critical_event_handlers registry for
  # integration:provider:staff_(un)assigned_*; the event-id idempotency gate
  # prevents double execution). The bus is keyed on the Provider context module,
  # so dispatch explicitly through `Provider`, not this sub-module.
  defp dispatch_assignment_event(event), do: DomainEventBus.dispatch(Provider, event)

  defp insert_program_staff_assignment(attrs) do
    %ProgramStaffAssignment{}
    |> ProgramStaffAssignment.create_changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, assignment} ->
        {:ok, assignment}

      {:error, %Ecto.Changeset{} = changeset} ->
        if EctoErrorHelpers.any_unique_constraint_violation?(changeset.errors) do
          {:error, :already_assigned}
        else
          {:error, changeset}
        end
    end
  end

  defp unassign_program_staff_assignment(program_id, staff_member_id) do
    ProgramStaffAssignment
    |> where(
      [a],
      a.program_id == ^program_id and a.staff_member_id == ^staff_member_id and
        is_nil(a.unassigned_at)
    )
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      assignment ->
        assignment
        |> ProgramStaffAssignment.unassign_changeset()
        |> Repo.update()
    end
  end

  # Active assignments (never unassigned), oldest-first — shared base for the
  # three list_active_assignments_* reads above.
  defp active_assignments_query do
    from a in ProgramStaffAssignment,
      where: is_nil(a.unassigned_at),
      order_by: [asc: a.assigned_at]
  end

  # Empty tags = staff sees all programs; populated tags restrict to matching categories.
  defp filter_programs_by_tags(programs, []), do: programs

  defp filter_programs_by_tags(programs, tags) when is_list(tags) do
    Enum.filter(programs, &(&1.category in tags))
  end
end
