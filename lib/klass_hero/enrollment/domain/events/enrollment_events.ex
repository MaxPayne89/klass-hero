defmodule KlassHero.Enrollment.Domain.Events.EnrollmentEvents do
  @moduledoc """
  Factory module for creating Enrollment domain events.

  All event factories that accept a caller-supplied `payload` merge it with
  a `base_payload` containing the canonical entity ID. `Map.merge/2` gives
  second-argument priority, so the canonical ID always wins.

  ## Events

  - `:participant_policy_set` - Emitted when a provider creates or updates
    participant eligibility restrictions for a program (upsert semantics).
  - `:bulk_invites_imported` - Emitted after a CSV/bulk import creates
    enrollment invite records for one or more programs.
  - `:invite_claimed` - Emitted when a guardian clicks an invite link and
    claims the enrollment invitation.
  - `:invite_resend_requested` - Emitted when a provider requests resending
    an enrollment invite email.
  - `:enrollment_cancelled` - Emitted when an admin cancels an enrollment.
  - `:enrollment_created` - Emitted when a new enrollment is persisted.
  - `:enrollment_confirmed` - Emitted when a provider approves a pending enrollment.
  """

  alias KlassHero.Shared.Domain.Events.DomainEvent

  @aggregate_type :enrollment

  def participant_policy_set(program_id, payload \\ %{}, opts \\ [])

  def participant_policy_set(program_id, payload, opts) when is_binary(program_id) and byte_size(program_id) > 0 do
    base_payload = %{program_id: program_id}

    DomainEvent.new(
      :participant_policy_set,
      program_id,
      @aggregate_type,
      Map.merge(payload, base_payload),
      opts
    )
  end

  def participant_policy_set(program_id, _payload, _opts) do
    raise ArgumentError,
          "participant_policy_set/3 requires a non-empty program_id string, got: #{inspect(program_id)}"
  end

  @doc """
  Creates a `:bulk_invites_imported` event after a batch CSV import.

  ## Parameters

  - `provider_id` — the provider who performed the import
  - `program_ids` — list of program IDs that received invites
  - `count` — total number of invite records created
  - `opts` — forwarded to `DomainEvent.new/5` (e.g. `:correlation_id`)
  """
  def bulk_invites_imported(provider_id, program_ids, count, opts \\ [])

  def bulk_invites_imported(provider_id, program_ids, count, opts)
      when is_binary(provider_id) and byte_size(provider_id) > 0 and is_list(program_ids) and is_integer(count) do
    DomainEvent.new(
      :bulk_invites_imported,
      provider_id,
      @aggregate_type,
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
  - `opts` — forwarded to `DomainEvent.new/5` (e.g. `:correlation_id`)
  """
  def invite_resend_requested(provider_id, invite_id, program_id, opts \\ [])

  def invite_resend_requested(provider_id, invite_id, program_id, opts)
      when is_binary(provider_id) and provider_id != "" and is_binary(invite_id) and invite_id != "" and
             is_binary(program_id) and program_id != "" do
    DomainEvent.new(
      :invite_resend_requested,
      invite_id,
      @aggregate_type,
      %{provider_id: provider_id, invite_id: invite_id, program_id: program_id},
      opts
    )
  end

  def invite_resend_requested(provider_id, invite_id, program_id, _opts) do
    raise ArgumentError,
          "invite_resend_requested/4 requires non-empty provider_id, invite_id, and program_id strings, " <>
            "got: #{inspect({provider_id, invite_id, program_id})}"
  end

  @doc """
  Creates an `:invite_claimed` event when a guardian clicks an invite link.

  ## Parameters

  - `invite_id` - the invite being claimed
  - `payload` - invite data including user_id, child info, guardian info
  - `opts` - forwarded to `DomainEvent.new/5` (e.g. `:correlation_id`)
  """
  def invite_claimed(invite_id, payload \\ %{}, opts \\ [])

  def invite_claimed(invite_id, payload, opts) when is_binary(invite_id) and byte_size(invite_id) > 0 do
    base_payload = %{invite_id: invite_id}

    DomainEvent.new(
      :invite_claimed,
      invite_id,
      :invite,
      Map.merge(payload, base_payload),
      opts
    )
  end

  def invite_claimed(invite_id, _payload, _opts) do
    raise ArgumentError,
          "invite_claimed/3 requires a non-empty invite_id string, got: #{inspect(invite_id)}"
  end

  @doc """
  Creates an `:enrollment_cancelled` event when an enrollment is cancelled.

  ## Parameters

  - `enrollment_id` — the cancelled enrollment's ID
  - `payload` — event data including program_id, child_id, parent_id, admin_id, reason, cancelled_at
  - `opts` — forwarded to `DomainEvent.new/5` (e.g. `:correlation_id`)
  """
  def enrollment_cancelled(enrollment_id, payload \\ %{}, opts \\ [])

  def enrollment_cancelled(enrollment_id, payload, opts)
      when is_binary(enrollment_id) and byte_size(enrollment_id) > 0 do
    base_payload = %{enrollment_id: enrollment_id}

    DomainEvent.new(
      :enrollment_cancelled,
      enrollment_id,
      @aggregate_type,
      Map.merge(payload, base_payload),
      opts
    )
  end

  def enrollment_cancelled(enrollment_id, _payload, _opts) do
    raise ArgumentError,
          "enrollment_cancelled/3 requires a non-empty enrollment_id string, got: #{inspect(enrollment_id)}"
  end

  @doc """
  Creates an `:enrollment_created` event when a new enrollment is persisted.

  ## Parameters

  - `enrollment_id` — the new enrollment's ID
  - `payload` — event data including child_id, parent_id, parent_user_id, program_id, status
  - `opts` — forwarded to `DomainEvent.new/5` (e.g. `:correlation_id`)
  """
  def enrollment_created(enrollment_id, payload \\ %{}, opts \\ [])

  def enrollment_created(enrollment_id, payload, opts) when is_binary(enrollment_id) and byte_size(enrollment_id) > 0 do
    base_payload = %{enrollment_id: enrollment_id}

    DomainEvent.new(
      :enrollment_created,
      enrollment_id,
      @aggregate_type,
      Map.merge(payload, base_payload),
      opts
    )
  end

  def enrollment_created(enrollment_id, _payload, _opts) do
    raise ArgumentError,
          "enrollment_created/3 requires a non-empty enrollment_id string, got: #{inspect(enrollment_id)}"
  end

  @doc """
  Creates an `:enrollment_confirmed` event when a provider approves a pending enrollment.

  ## Parameters

  - `enrollment_id` — the confirmed enrollment's ID
  - `payload` — event data including `program_id`, `child_id`, `parent_id`, `confirmed_at`
  - `opts` — forwarded to `DomainEvent.new/5` (e.g. `:correlation_id`)
  """
  def enrollment_confirmed(enrollment_id, payload \\ %{}, opts \\ [])

  def enrollment_confirmed(enrollment_id, payload, opts)
      when is_binary(enrollment_id) and byte_size(enrollment_id) > 0 do
    base_payload = %{enrollment_id: enrollment_id}

    DomainEvent.new(
      :enrollment_confirmed,
      enrollment_id,
      @aggregate_type,
      Map.merge(payload, base_payload),
      opts
    )
  end

  def enrollment_confirmed(enrollment_id, _payload, _opts) do
    raise ArgumentError,
          "enrollment_confirmed/3 requires a non-empty enrollment_id string, got: #{inspect(enrollment_id)}"
  end
end
