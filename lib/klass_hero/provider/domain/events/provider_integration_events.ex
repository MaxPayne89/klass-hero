defmodule KlassHero.Provider.Domain.Events.ProviderIntegrationEvents do
  @moduledoc """
  Factory module for creating Provider integration events.

  Integration events are the public contract between bounded contexts.

  ## Events

  - `:staff_member_invited` - Emitted when a staff member is invited to join a provider.
    The Accounts context reacts to send the invitation email (critical).

  - `:staff_assigned_to_program` - Emitted when a staff member is assigned to a program.
    The Messaging context reacts to update conversation participant access (critical).

  - `:staff_unassigned_from_program` - Emitted when a staff member is unassigned from a program.
    The Messaging context reacts to revoke conversation participant access (critical).

  - `:incident_reported` - Emitted when a provider submits an incident report.
    Downstream contexts (e.g., admin dashboards, notifications) can react to safety events (critical).
  """

  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  @typedoc "Payload for `:staff_member_invited` events."
  @type staff_member_invited_payload :: %{
          required(:staff_member_id) => String.t(),
          optional(atom()) => term()
        }

  @source_context :provider
  @staff_entity_type :staff_member
  @incident_report_entity_type :incident_report

  @doc """
  Creates a `staff_member_invited` integration event.

  Marked `:critical` by default — the Accounts context must send the invitation email.

  ## Parameters

  - `staff_member_id` - The ID of the invited staff member
  - `payload` - Additional event-specific data (provider_id, email, first_name, etc.)
  - `opts` - Metadata options (correlation_id, causation_id)

  ## Payload Fields

  Standard payload includes:
  - `staff_member_id` - The staff member's ID

  ## Raises

  - `ArgumentError` if `staff_member_id` is nil or empty

  ## Examples

      iex> event = ProviderIntegrationEvents.staff_member_invited("staff-uuid")
      iex> event.event_type
      :staff_member_invited
      iex> event.source_context
      :provider
      iex> event.entity_type
      :staff_member
      iex> IntegrationEvent.critical?(event)
      true
  """
  def staff_member_invited(staff_member_id, payload \\ %{}, opts \\ [])

  def staff_member_invited(staff_member_id, payload, opts)
      when is_binary(staff_member_id) and byte_size(staff_member_id) > 0 do
    base_payload = %{staff_member_id: staff_member_id}
    opts = Keyword.put_new(opts, :criticality, :critical)

    IntegrationEvent.new(
      :staff_member_invited,
      @source_context,
      @staff_entity_type,
      staff_member_id,
      # Trigger: caller may pass a conflicting :staff_member_id in payload
      # Why: base_payload contains the canonical staff_member_id from the function argument
      # Outcome: base_payload keys always win, preventing accidental overwrite
      Map.merge(payload, base_payload),
      opts
    )
  end

  def staff_member_invited(staff_member_id, _payload, _opts) do
    raise ArgumentError,
          "staff_member_invited/3 requires a non-empty staff_member_id string, got: #{inspect(staff_member_id)}"
  end

  @doc """
  Creates a `staff_assigned_to_program` integration event.

  Marked `:critical` by default — the Messaging context must update conversation access.

  ## Parameters

  - `staff_member_id` - The ID of the assigned staff member
  - `payload` - Additional event-specific data (provider_id, program_id, staff_user_id, assigned_at)
  - `opts` - Metadata options (correlation_id, causation_id)

  ## Raises

  - `ArgumentError` if `staff_member_id` is nil or empty
  """
  def staff_assigned_to_program(staff_member_id, payload \\ %{}, opts \\ [])

  def staff_assigned_to_program(staff_member_id, payload, opts)
      when is_binary(staff_member_id) and byte_size(staff_member_id) > 0 do
    base_payload = %{staff_member_id: staff_member_id}
    opts = Keyword.put_new(opts, :criticality, :critical)

    IntegrationEvent.new(
      :staff_assigned_to_program,
      @source_context,
      @staff_entity_type,
      staff_member_id,
      # Trigger: caller may pass a conflicting key in payload
      # Why: base_payload contains the canonical IDs from the function argument
      # Outcome: base_payload keys always win, preventing accidental overwrite
      Map.merge(payload, base_payload),
      opts
    )
  end

  def staff_assigned_to_program(staff_member_id, _payload, _opts) do
    raise ArgumentError,
          "staff_assigned_to_program/3 requires a non-empty staff_member_id string, got: #{inspect(staff_member_id)}"
  end

  @doc """
  Creates a `staff_unassigned_from_program` integration event.

  Marked `:critical` by default — the Messaging context must revoke conversation access.

  ## Parameters

  - `staff_member_id` - The ID of the unassigned staff member
  - `payload` - Additional event-specific data (provider_id, program_id, staff_user_id, unassigned_at)
  - `opts` - Metadata options (correlation_id, causation_id)

  ## Raises

  - `ArgumentError` if `staff_member_id` is nil or empty
  """
  def staff_unassigned_from_program(staff_member_id, payload \\ %{}, opts \\ [])

  def staff_unassigned_from_program(staff_member_id, payload, opts)
      when is_binary(staff_member_id) and byte_size(staff_member_id) > 0 do
    base_payload = %{staff_member_id: staff_member_id}
    opts = Keyword.put_new(opts, :criticality, :critical)

    IntegrationEvent.new(
      :staff_unassigned_from_program,
      @source_context,
      @staff_entity_type,
      staff_member_id,
      # Trigger: caller may pass a conflicting key in payload
      # Why: base_payload contains the canonical IDs from the function argument
      # Outcome: base_payload keys always win, preventing accidental overwrite
      Map.merge(payload, base_payload),
      opts
    )
  end

  def staff_unassigned_from_program(staff_member_id, _payload, _opts) do
    raise ArgumentError,
          "staff_unassigned_from_program/3 requires a non-empty staff_member_id string, got: #{inspect(staff_member_id)}"
  end

  @doc """
  Creates an `incident_reported` integration event.

  Marked `:critical` by default — downstream consumers (admin dashboards, notifications)
  must receive safety events durably.

  ## Parameters

  - `incident_report_id` - The ID of the reported incident
  - `payload` - Pass-through payload from the domain event (no sensitive fields)
  - `opts` - Metadata options (correlation_id, causation_id)

  ## Raises

  - `ArgumentError` if `incident_report_id` is nil or empty
  """
  def incident_reported(incident_report_id, payload \\ %{}, opts \\ [])

  def incident_reported(incident_report_id, payload, opts)
      when is_binary(incident_report_id) and byte_size(incident_report_id) > 0 do
    base_payload = %{incident_report_id: incident_report_id}
    opts = Keyword.put_new(opts, :criticality, :critical)

    IntegrationEvent.new(
      :incident_reported,
      @source_context,
      @incident_report_entity_type,
      incident_report_id,
      # Trigger: caller may pass a conflicting :incident_report_id in payload
      # Why: base_payload contains the canonical incident_report_id from the function argument
      # Outcome: base_payload keys always win, preventing accidental overwrite
      Map.merge(payload, base_payload),
      opts
    )
  end

  def incident_reported(incident_report_id, _payload, _opts) do
    raise ArgumentError,
          "incident_reported/3 requires a non-empty incident_report_id string, got: #{inspect(incident_report_id)}"
  end
end
