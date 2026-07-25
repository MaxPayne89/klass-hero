defmodule KlassHero.Provider.Domain.Events.ProviderEvents do
  @moduledoc """
  Factory module for creating Provider domain events.

  ## Event Types

  - `staff_assigned_to_program` - A staff member was assigned to a program
  - `staff_unassigned_from_program` - A staff member was unassigned from a program

  All events are returned as `DomainEvent` structs.
  """

  alias KlassHero.Provider.ProgramStaffAssignment
  alias KlassHero.Provider.ProviderProfile
  alias KlassHero.Provider.StaffMember
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  @aggregate_type :provider

  @doc "Creates a provider_verified integration event."
  @spec provider_verified(ProviderProfile.t(), String.t()) :: IntegrationEvent.t()
  def provider_verified(%ProviderProfile{} = profile, admin_id) do
    IntegrationEvent.new(:provider_verified, @aggregate_type, @aggregate_type, profile.id, %{
      provider_id: profile.id,
      business_name: profile.business_name,
      verified_at: profile.verified_at,
      admin_id: admin_id
    })
  end

  @doc "Creates a provider_unverified integration event."
  @spec provider_unverified(ProviderProfile.t(), String.t()) :: IntegrationEvent.t()
  def provider_unverified(%ProviderProfile{} = profile, admin_id) do
    IntegrationEvent.new(:provider_unverified, @aggregate_type, @aggregate_type, profile.id, %{
      provider_id: profile.id,
      business_name: profile.business_name,
      admin_id: admin_id
    })
  end

  @doc "Creates a staff_assigned_to_program event."
  @spec staff_assigned_to_program(ProgramStaffAssignment.t(), StaffMember.t(), keyword()) ::
          DomainEvent.t()
  def staff_assigned_to_program(%ProgramStaffAssignment{} = assignment, %StaffMember{} = staff_member, opts \\ []) do
    payload = %{
      provider_id: assignment.provider_id,
      program_id: assignment.program_id,
      staff_member_id: assignment.staff_member_id,
      staff_user_id: staff_member.user_id,
      assigned_at: assignment.assigned_at
    }

    DomainEvent.new(:staff_assigned_to_program, assignment.id, @aggregate_type, payload, opts)
  end

  @doc "Creates a staff_unassigned_from_program event."
  @spec staff_unassigned_from_program(ProgramStaffAssignment.t(), StaffMember.t(), keyword()) ::
          DomainEvent.t()
  def staff_unassigned_from_program(%ProgramStaffAssignment{} = assignment, %StaffMember{} = staff_member, opts \\ []) do
    payload = %{
      provider_id: assignment.provider_id,
      program_id: assignment.program_id,
      staff_member_id: assignment.staff_member_id,
      staff_user_id: staff_member.user_id,
      unassigned_at: assignment.unassigned_at
    }

    DomainEvent.new(
      :staff_unassigned_from_program,
      assignment.id,
      @aggregate_type,
      payload,
      opts
    )
  end
end
