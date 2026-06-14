defmodule KlassHero.Provider.Adapters.Driven.Persistence.Repositories.ProgramStaffAssignmentRepository do
  @moduledoc """
  Repository implementation for storing and retrieving program staff assignments.

  Implements the ForStoringProgramStaffAssignments port.
  """

  @behaviour KlassHero.Provider.Domain.Ports.ForQueryingProgramStaffAssignments
  @behaviour KlassHero.Provider.Domain.Ports.ForStoringProgramStaffAssignments

  use KlassHero.Shared.Interaction

  import Ecto.Query

  alias KlassHero.Provider.Adapters.Driven.Persistence.Mappers.ProgramStaffAssignmentMapper
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.ProgramStaffAssignmentSchema
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.EctoErrorHelpers
  alias KlassHero.Shared.Adapters.Driven.Persistence.MapperHelpers

  require Logger

  @impl true
  def create(attrs) when is_map(attrs) do
    db_interaction operation: :create, entity: "program_staff_assignment" do
      %ProgramStaffAssignmentSchema{}
      |> ProgramStaffAssignmentSchema.create_changeset(attrs)
      |> Repo.insert()
      |> case do
        {:ok, schema} ->
          {:ok, ProgramStaffAssignmentMapper.to_domain(schema)}

        {:error, %Ecto.Changeset{} = changeset} ->
          if EctoErrorHelpers.any_unique_constraint_violation?(changeset.errors) do
            {:error, :already_assigned}
          else
            Logger.warning("Unexpected changeset error creating program staff assignment",
              errors: inspect(changeset.errors)
            )

            {:error, changeset}
          end
      end
    end
  end

  @impl true
  def unassign(program_id, staff_member_id) do
    db_interaction operation: :unassign, entity: "program_staff_assignment" do
      ProgramStaffAssignmentSchema
      |> where(
        [a],
        a.program_id == ^program_id and a.staff_member_id == ^staff_member_id and
          is_nil(a.unassigned_at)
      )
      |> Repo.one()
      |> case do
        nil ->
          {:error, :not_found}

        schema ->
          schema
          |> ProgramStaffAssignmentSchema.unassign_changeset()
          |> Repo.update()
          |> case do
            {:ok, updated} -> {:ok, ProgramStaffAssignmentMapper.to_domain(updated)}
            {:error, changeset} -> {:error, changeset}
          end
      end
    end
  end

  @impl true
  def list_active_for_program(program_id) do
    db_interaction operation: :list_active_for_program, entity: "program_staff_assignment" do
      ProgramStaffAssignmentSchema
      |> where([a], a.program_id == ^program_id and is_nil(a.unassigned_at))
      |> order_by([a], asc: a.assigned_at)
      |> Repo.all()
      |> MapperHelpers.to_domain_list(ProgramStaffAssignmentMapper)
    end
  end

  @impl true
  def list_active_for_staff_member(staff_member_id) do
    db_interaction operation: :list_active_for_staff_member, entity: "program_staff_assignment" do
      ProgramStaffAssignmentSchema
      |> where([a], a.staff_member_id == ^staff_member_id and is_nil(a.unassigned_at))
      |> order_by([a], asc: a.assigned_at)
      |> Repo.all()
      |> MapperHelpers.to_domain_list(ProgramStaffAssignmentMapper)
    end
  end

  @impl true
  def list_active_for_provider(provider_id) do
    db_interaction operation: :list_active_for_provider, entity: "program_staff_assignment" do
      ProgramStaffAssignmentSchema
      |> where([a], a.provider_id == ^provider_id and is_nil(a.unassigned_at))
      |> order_by([a], asc: a.assigned_at)
      |> Repo.all()
      |> MapperHelpers.to_domain_list(ProgramStaffAssignmentMapper)
    end
  end
end
