defmodule KlassHero.Provider.Assignments do
  @moduledoc """
  Program ↔ staff assignment commands and queries for the Provider context.

  Assignment writes emit domain events on the Provider bus (promoted to durable
  integration events); reads expose active assignments and the staff behind them.
  Reached through `KlassHero.Provider`'s public API.
  """

  use KlassHero.Shared.Tracing

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias KlassHero.ProgramCatalog
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

  `attrs.provider_id` is the tenancy authority and must come from the
  authenticated scope, never from client input. Both the staff member and the
  program are verified to belong to it.

  Returns:
  - `{:ok, ProgramStaffAssignment.t()}` on success
  - `{:error, :already_assigned}` if the staff member is already assigned
  - `{:error, :not_found}` if the staff member or program does not exist **or is
    owned by another provider** (IDOR guard — the two are indistinguishable)
  """
  @spec assign_staff_to_program(map()) ::
          {:ok, ProgramStaffAssignment.t()}
          | {:error, :already_assigned | :not_found | term()}
  def assign_staff_to_program(%{provider_id: provider_id} = attrs) when is_map(attrs) do
    context_span entity: "program_staff_assignment" do
      with {:ok, staff_member} <- Provider.get_staff_member(attrs.staff_member_id, provider_id),
           :ok <- ensure_program_owned(attrs.program_id, provider_id),
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
  Unassigns a staff member from a program owned by `provider_id`.

  Returns:
  - `{:ok, ProgramStaffAssignment.t()}` on success
  - `{:error, :not_found}` if no active assignment exists **or it belongs to
    another provider** (IDOR guard — the two are indistinguishable). The lookup
    query itself is provider-scoped, so a foreign row is never reached, let alone
    updated.
  """
  @spec unassign_staff_from_program(String.t(), String.t(), String.t()) ::
          {:ok, ProgramStaffAssignment.t()} | {:error, :not_found | term()}
  def unassign_staff_from_program(program_id, staff_member_id, provider_id)
      when is_binary(program_id) and is_binary(staff_member_id) and is_binary(provider_id) do
    context_span entity: "program_staff_assignment" do
      with {:ok, staff_member} <- Provider.get_staff_member(staff_member_id, provider_id),
           {:ok, assignment} <-
             unassign_program_staff_assignment(program_id, staff_member_id, provider_id) do
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

  @doc """
  Promotes a staff member to the program's lead instructor — the single source
  of truth for "the lead" (replaces the old `programs.instructor_*` snapshot).

  Idempotent and transactional: any previous lead on the program is cleared and
  the target assignment is flagged lead in one transaction, so the
  `program_staff_assignments_single_lead` partial unique index is never violated
  mid-flight. Creates an active assignment when the staff member has none yet.

  Returns `{:ok, ProgramStaffAssignment.t()}` or `{:error, :not_found}` when the
  staff member **or the program** does not exist or is owned by another provider
  (IDOR guard — the cases are indistinguishable, so no cross-tenant assignment is
  ever written).
  """
  @spec set_lead_instructor(String.t(), String.t(), String.t()) ::
          {:ok, ProgramStaffAssignment.t()} | {:error, :not_found | term()}
  def set_lead_instructor(program_id, staff_member_id, provider_id)
      when is_binary(program_id) and is_binary(staff_member_id) and is_binary(provider_id) do
    context_span entity: "program_staff_assignment" do
      # Both sides are checked (see @doc): a competitor's staff must never attach to
      # this publicly-rendered program, nor this provider's staff to their program.
      with {:ok, staff_member} <- Provider.get_staff_member(staff_member_id, provider_id),
           :ok <- ensure_program_owned(program_id, provider_id) do
        Multi.new()
        |> Multi.update_all(
          :clear_other_leads,
          other_active_leads_query(program_id, staff_member_id, provider_id),
          set: [is_lead_instructor: false]
        )
        |> Multi.run(:lead, fn repo, _ -> upsert_lead(repo, program_id, staff_member) end)
        |> Repo.transaction()
        |> case do
          {:ok, %{lead: lead}} -> {:ok, lead}
          {:error, _step, reason, _changes} -> {:error, reason}
        end
      end
    end
  end

  @doc """
  Clears the lead instructor on a program owned by `provider_id`, leaving the
  assignment otherwise active.

  No-op when the program has no lead **or belongs to another provider** — the
  update query is provider-scoped, so a foreign lead is never reached.
  """
  @spec clear_lead_instructor(String.t(), String.t()) :: :ok
  def clear_lead_instructor(program_id, provider_id) when is_binary(program_id) and is_binary(provider_id) do
    active_leads_query(program_id, provider_id)
    |> Repo.update_all(set: [is_lead_instructor: false])

    :ok
  end

  @doc """
  Returns the program's lead instructor as a display map
  (`%{id, name, headshot_url}`), or `nil` when there is no lead.
  """
  @spec get_lead_instructor(String.t()) :: %{id: String.t(), name: String.t(), headshot_url: String.t() | nil} | nil
  def get_lead_instructor(program_id) when is_binary(program_id) do
    lead_staff_query()
    |> where([_s, a], a.program_id == ^program_id)
    |> select([s, _a], s)
    |> Repo.one()
    |> to_lead_map()
  end

  @doc """
  Batch lead-instructor read keyed by `program_id`, for list views that would
  otherwise N+1. Programs without a lead are omitted from the map.
  """
  @spec list_lead_instructors_for_programs([String.t()]) :: %{optional(String.t()) => map()}
  def list_lead_instructors_for_programs([]), do: %{}

  def list_lead_instructors_for_programs(program_ids) when is_list(program_ids) do
    lead_staff_query()
    |> where([_s, a], a.program_id in ^program_ids)
    |> select([s, a], {a.program_id, s})
    |> Repo.all()
    |> Map.new(fn {program_id, staff} -> {program_id, to_lead_map(staff)} end)
  end

  # Active lead assignment(s) for a program (should be at most one via the index),
  # scoped to the owning provider so no mutation can reach a foreign lead.
  defp active_leads_query(program_id, provider_id) do
    from a in ProgramStaffAssignment.owned_by(provider_id),
      where: a.program_id == ^program_id and a.is_lead_instructor and is_nil(a.unassigned_at)
  end

  # Active leads for the program EXCEPT the incoming staff member — cleared first
  # so promoting a new lead never collides with the partial unique index.
  defp other_active_leads_query(program_id, staff_member_id, provider_id) do
    from a in active_leads_query(program_id, provider_id),
      where: a.staff_member_id != ^staff_member_id
  end

  # Staff joined to their active lead assignment; callers narrow by program and
  # add their own select (single-record vs {program_id, staff} batch).
  defp lead_staff_query do
    from s in StaffMember,
      join: a in ProgramStaffAssignment,
      on: a.staff_member_id == s.id,
      where: a.is_lead_instructor and is_nil(a.unassigned_at)
  end

  defp upsert_lead(repo, program_id, staff_member) do
    # staff_member is already proven owned by the caller's provider, so its
    # provider_id is the tenancy key for both the lookup and the inserted row.
    case repo.one(active_assignment_scope(program_id, staff_member.id, staff_member.provider_id)) do
      nil ->
        %ProgramStaffAssignment{}
        |> ProgramStaffAssignment.create_changeset(%{
          provider_id: staff_member.provider_id,
          program_id: program_id,
          staff_member_id: staff_member.id,
          assigned_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
          is_lead_instructor: true
        })
        |> repo.insert()

      assignment ->
        assignment
        |> ProgramStaffAssignment.lead_changeset(true)
        |> repo.update()
    end
  end

  # The single active (program, staff) assignment for the provider, if one exists.
  defp active_assignment_scope(program_id, staff_member_id, provider_id) do
    from a in ProgramStaffAssignment.owned_by(provider_id),
      where:
        a.program_id == ^program_id and a.staff_member_id == ^staff_member_id and
          is_nil(a.unassigned_at)
  end

  defp to_lead_map(nil), do: nil

  defp to_lead_map(%StaffMember{} = staff) do
    %{id: staff.id, name: StaffMember.full_name(staff), headshot_url: staff.headshot_url}
  end

  # Programs are owned by Program Catalog, so ownership is read through its public
  # facade — strongly consistent, unlike the `provider_programs` projection, whose
  # lag would reject a lead set immediately after the program is created.
  # Foreign ≡ missing, matching the staff guard.
  defp ensure_program_owned(program_id, provider_id) do
    acl_span source: "provider", target: "program_catalog" do
      case ProgramCatalog.get_program_by_id(program_id) do
        {:ok, %{provider_id: ^provider_id}} -> :ok
        _foreign_or_missing -> {:error, :not_found}
      end
    end
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

  defp unassign_program_staff_assignment(program_id, staff_member_id, provider_id) do
    ProgramStaffAssignment
    |> ProgramStaffAssignment.owned_by(provider_id)
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
