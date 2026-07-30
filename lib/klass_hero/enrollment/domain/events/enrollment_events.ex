defmodule KlassHero.Enrollment.Domain.Events.EnrollmentEvents do
  @moduledoc """
  Factory module for creating Enrollment events.

  Factories that accept a caller-supplied `payload` overwrite its canonical
  entity id with the id argument, so the field consumers key on cannot be
  displaced by a caller.

  ## Events

  - `:participant_policy_set` - Emitted when a provider creates or updates
    participant eligibility restrictions for a program (upsert semantics).
  - `:invite_claimed` - Emitted when a parent claims an enrollment invite.
  - `:enrollment_created` - Emitted when a new enrollment is persisted.
  - `:enrollment_cancelled` - Emitted when an enrollment is cancelled.
  - `:bulk_invites_imported` - Emitted after a CSV/bulk import creates
    enrollment invite records for one or more programs.
  - `:invite_resend_requested` - Emitted when a provider resends an invite.

  The last two cross no context boundary: they drive same-context handlers on
  the `DomainEventBus`, so no consumer is registered for them and the outbox
  does not stage them.
  """

  alias KlassHero.Shared.Domain.Events.Event

  @source_context :enrollment

  @doc """
  Creates a `:participant_policy_set` event.
  """
  def participant_policy_set(program_id, payload \\ %{}, opts \\ [])

  def participant_policy_set(program_id, payload, opts) when is_binary(program_id) and byte_size(program_id) > 0 do
    build(:participant_policy_set, :participant_policy, :program_id, program_id, payload, opts)
  end

  def participant_policy_set(program_id, _payload, _opts) do
    raise ArgumentError,
          "participant_policy_set/3 requires a non-empty program_id string, got: #{inspect(program_id)}"
  end

  @doc """
  Creates an `:invite_claimed` event.
  """
  def invite_claimed(invite_id, payload \\ %{}, opts \\ [])

  def invite_claimed(invite_id, payload, opts) when is_binary(invite_id) and byte_size(invite_id) > 0 do
    build(:invite_claimed, :invite, :invite_id, invite_id, payload, opts)
  end

  def invite_claimed(invite_id, _payload, _opts) do
    raise ArgumentError,
          "invite_claimed/3 requires a non-empty invite_id string, got: #{inspect(invite_id)}"
  end

  @doc """
  Creates an `:enrollment_created` event.
  """
  def enrollment_created(enrollment_id, payload \\ %{}, opts \\ [])

  def enrollment_created(enrollment_id, payload, opts) when is_binary(enrollment_id) and byte_size(enrollment_id) > 0 do
    build(:enrollment_created, :enrollment, :enrollment_id, enrollment_id, payload, opts)
  end

  def enrollment_created(enrollment_id, _payload, _opts) do
    raise ArgumentError,
          "enrollment_created/3 requires a non-empty enrollment_id string, got: #{inspect(enrollment_id)}"
  end

  @doc """
  Creates an `:enrollment_cancelled` event.
  """
  def enrollment_cancelled(enrollment_id, payload \\ %{}, opts \\ [])

  def enrollment_cancelled(enrollment_id, payload, opts)
      when is_binary(enrollment_id) and byte_size(enrollment_id) > 0 do
    build(:enrollment_cancelled, :enrollment, :enrollment_id, enrollment_id, payload, opts)
  end

  def enrollment_cancelled(enrollment_id, _payload, _opts) do
    raise ArgumentError,
          "enrollment_cancelled/3 requires a non-empty enrollment_id string, got: #{inspect(enrollment_id)}"
  end

  @doc """
  Creates a `:bulk_invites_imported` event after a CSV/bulk import.

  ## Parameters

  - `provider_id` — the provider who imported
  - `program_ids` — the programs invites were created for
  - `count` — how many invites were created
  - `opts` — metadata options (e.g. `:correlation_id`)
  """
  def bulk_invites_imported(provider_id, program_ids, count, opts \\ [])

  def bulk_invites_imported(provider_id, program_ids, count, opts)
      when is_binary(provider_id) and byte_size(provider_id) > 0 and is_list(program_ids) and is_integer(count) do
    Event.new(
      :bulk_invites_imported,
      @source_context,
      :provider,
      provider_id,
      %{provider_id: provider_id, program_ids: program_ids, count: count},
      opts
    )
  end

  def bulk_invites_imported(provider_id, _program_ids, _count, _opts) do
    raise ArgumentError,
          "bulk_invites_imported/4 requires a non-empty provider_id string, " <>
            "a list of program_ids, and an integer count, got: #{inspect(provider_id)}"
  end

  @doc """
  Creates an `:invite_resend_requested` event when a provider resends an invite.

  ## Parameters

  - `provider_id` — the provider who requested the resend
  - `invite_id` — the invite being resent
  - `program_id` — the program the invite belongs to
  - `opts` — metadata options (e.g. `:correlation_id`)
  """
  def invite_resend_requested(provider_id, invite_id, program_id, opts \\ [])

  def invite_resend_requested(provider_id, invite_id, program_id, opts)
      when is_binary(provider_id) and provider_id != "" and is_binary(invite_id) and invite_id != "" and
             is_binary(program_id) and program_id != "" do
    Event.new(
      :invite_resend_requested,
      @source_context,
      :invite,
      invite_id,
      %{provider_id: provider_id, invite_id: invite_id, program_id: program_id},
      opts
    )
  end

  def invite_resend_requested(provider_id, invite_id, program_id, _opts) do
    raise ArgumentError,
          "invite_resend_requested/4 requires non-empty provider_id, invite_id, and program_id strings, " <>
            "got: #{inspect({provider_id, invite_id, program_id})}"
  end

  defp build(event_type, entity_type, id_key, id, payload, opts) do
    Event.new(
      event_type,
      @source_context,
      entity_type,
      id,
      # Overwrites rather than merges: the id argument wins over any caller-supplied one.
      Map.put(payload, id_key, id),
      opts
    )
  end
end
