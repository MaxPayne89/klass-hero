defmodule KlassHero.Provider.Domain.Events.ProviderEvents do
  @moduledoc """
  Factory module for creating Provider events.

  ## Event Types

  - `provider_verified` / `provider_unverified` - An admin changed a provider's
    verification status. **No consumer is registered for these since #1195**, so
    `Outbox.stage/2` drops them rather than staging: Program Catalog's listing
    projection used to subscribe, but program cards now read verification through
    `Provider.get_trust_states/1` per render. They are still built here so that
    registering a consumer in `config/config.exs` is all it takes to revive delivery.
  - `staff_member_invited` - A staff invitation was created.
  - `staff_assigned_to_program` / `staff_unassigned_from_program` - A staff
    member's program assignment changed. Messaging reacts by adding
    or removing the staff member from the program's conversation.
    `staff_assigned_to_program` is **also replayed on invite acceptance**, once per
    standing assignment: a program assigned before the invite was claimed announced
    a nil `staff_user_id`, which consumers skip (#1312).
  - `staff_member_deactivated` - A staff member's employment link ended. Read
    tables holding a denormalised staff name clear it; a read filter cannot,
    because the name is a stored column.

  The staff assignment events carry the **staff member** as their entity, not
  the assignment row: consumers key on who was assigned, not on which row
  recorded it.
  """

  alias KlassHero.Provider.ProgramStaffAssignment
  alias KlassHero.Provider.ProviderProfile
  alias KlassHero.Provider.StaffMember
  alias KlassHero.Shared.Domain.Events.Event

  @source_context :provider
  @provider_entity_type :provider
  @staff_entity_type :staff_member

  @doc "Creates a provider_verified event."
  @spec provider_verified(ProviderProfile.t(), String.t()) :: Event.t()
  def provider_verified(%ProviderProfile{} = profile, admin_id) do
    Event.new(:provider_verified, @source_context, @provider_entity_type, profile.id, %{
      provider_id: profile.id,
      business_name: profile.business_name,
      verified_at: profile.verified_at,
      admin_id: admin_id
    })
  end

  @doc "Creates a provider_unverified event."
  @spec provider_unverified(ProviderProfile.t(), String.t()) :: Event.t()
  def provider_unverified(%ProviderProfile{} = profile, admin_id) do
    Event.new(:provider_unverified, @source_context, @provider_entity_type, profile.id, %{
      provider_id: profile.id,
      business_name: profile.business_name,
      admin_id: admin_id
    })
  end

  @doc """
  Creates a `staff_member_invited` event.

  Accounts reacts by sending the invitation email, so a lost event is a staff
  member who never hears they were invited.
  """
  def staff_member_invited(staff_member_id, payload \\ %{}, opts \\ [])

  def staff_member_invited(staff_member_id, payload, _opts)
      when is_binary(staff_member_id) and byte_size(staff_member_id) > 0 do
    Event.new(
      :staff_member_invited,
      @source_context,
      @staff_entity_type,
      staff_member_id,
      Map.put(payload, :staff_member_id, staff_member_id)
    )
  end

  def staff_member_invited(staff_member_id, _payload, _opts) do
    raise ArgumentError,
          "staff_member_invited/3 requires a non-empty staff_member_id string, got: #{inspect(staff_member_id)}"
  end

  @doc "Creates a staff_assigned_to_program event."
  @spec staff_assigned_to_program(ProgramStaffAssignment.t(), StaffMember.t(), keyword()) ::
          Event.t()
  def staff_assigned_to_program(%ProgramStaffAssignment{} = assignment, %StaffMember{} = staff_member, opts \\ []) do
    assignment_event(:staff_assigned_to_program, assignment, staff_member, opts)
  end

  @doc "Creates a staff_unassigned_from_program event."
  @spec staff_unassigned_from_program(ProgramStaffAssignment.t(), StaffMember.t(), keyword()) ::
          Event.t()
  def staff_unassigned_from_program(%ProgramStaffAssignment{} = assignment, %StaffMember{} = staff_member, opts \\ []) do
    assignment_event(:staff_unassigned_from_program, assignment, staff_member, opts)
  end

  @doc """
  Creates a `staff_member_deactivated` event.

  Carries no `program_ids`: consumers hold `staff_member_id` on their own rows,
  so scoping by the staff member is both narrower and immune to the assignment
  set changing between staging and delivery. No timestamp either — no consumer
  reads one.
  """
  @spec staff_member_deactivated(StaffMember.t(), keyword()) :: Event.t()
  def staff_member_deactivated(%StaffMember{} = staff_member, _opts \\ []) do
    payload = %{
      provider_id: staff_member.provider_id,
      staff_member_id: staff_member.id,
      staff_user_id: staff_member.user_id
    }

    Event.new(
      :staff_member_deactivated,
      @source_context,
      @staff_entity_type,
      staff_member.id,
      payload
    )
  end

  # assigned_at/unassigned_at are deliberately absent: no consumer reads them.
  defp assignment_event(event_type, assignment, staff_member, _opts) do
    payload = %{
      provider_id: assignment.provider_id,
      program_id: assignment.program_id,
      staff_member_id: assignment.staff_member_id,
      staff_user_id: staff_member.user_id
    }

    Event.new(
      event_type,
      @source_context,
      @staff_entity_type,
      assignment.staff_member_id,
      payload
    )
  end
end
