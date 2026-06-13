defmodule KlassHero.Enrollment.Domain.Events.EnrollmentIntegrationEvents do
  @moduledoc """
  Factory module for creating Enrollment integration events.

  Integration events are the public contract between bounded contexts.
  All event factories that accept a caller-supplied `payload` merge it with
  a `base_payload` containing the canonical entity ID. `Map.merge/2` gives
  second-argument priority, so the canonical ID always wins.

  ## Events

  - `:participant_policy_set` - Emitted when participant eligibility restrictions
    are created or updated. Downstream contexts can react (e.g., search indexing).
  - `:invite_claimed` - Emitted when a guardian claims an enrollment invite.
    Downstream contexts can react to create profiles or link existing users.
  - `:enrollment_cancelled` - Emitted when an admin cancels an enrollment.
    Downstream contexts can react to notify affected parties or
    update reporting data.
  - `:enrollment_created` - Emitted when a new enrollment is persisted.
    Downstream contexts can react to link enrolled children or
    update conversation participant data.
  """

  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  @typedoc "Payload for `:participant_policy_set` events."
  @type participant_policy_set_payload :: %{
          required(:program_id) => String.t(),
          optional(atom()) => term()
        }

  @typedoc "Payload for `:invite_claimed` events."
  @type invite_claimed_payload :: %{
          required(:invite_id) => String.t(),
          optional(atom()) => term()
        }

  @typedoc "Payload for `:enrollment_cancelled` events."
  @type enrollment_cancelled_payload :: %{
          required(:enrollment_id) => String.t(),
          optional(atom()) => term()
        }

  @source_context :enrollment
  @entity_type :participant_policy

  def participant_policy_set(program_id, payload \\ %{}, opts \\ [])

  def participant_policy_set(program_id, payload, opts) when is_binary(program_id) and byte_size(program_id) > 0 do
    base_payload = %{program_id: program_id}

    IntegrationEvent.new(
      :participant_policy_set,
      @source_context,
      @entity_type,
      program_id,
      Map.merge(payload, base_payload),
      opts
    )
  end

  def participant_policy_set(program_id, _payload, _opts) do
    raise ArgumentError,
          "participant_policy_set/3 requires a non-empty program_id string, got: #{inspect(program_id)}"
  end

  def invite_claimed(invite_id, payload \\ %{}, opts \\ [])

  def invite_claimed(invite_id, payload, opts) when is_binary(invite_id) and byte_size(invite_id) > 0 do
    base_payload = %{invite_id: invite_id}

    IntegrationEvent.new(
      :invite_claimed,
      @source_context,
      # @entity_type is :participant_policy; invites are a separate entity type
      :invite,
      invite_id,
      Map.merge(payload, base_payload),
      opts
    )
  end

  def invite_claimed(invite_id, _payload, _opts) do
    raise ArgumentError,
          "invite_claimed/3 requires a non-empty invite_id string, got: #{inspect(invite_id)}"
  end

  def enrollment_cancelled(enrollment_id, payload \\ %{}, opts \\ [])

  def enrollment_cancelled(enrollment_id, payload, opts)
      when is_binary(enrollment_id) and byte_size(enrollment_id) > 0 do
    base_payload = %{enrollment_id: enrollment_id}

    IntegrationEvent.new(
      :enrollment_cancelled,
      @source_context,
      # @entity_type is :participant_policy; enrollments are a separate entity type
      :enrollment,
      enrollment_id,
      Map.merge(payload, base_payload),
      opts
    )
  end

  def enrollment_cancelled(enrollment_id, _payload, _opts) do
    raise ArgumentError,
          "enrollment_cancelled/3 requires a non-empty enrollment_id string, got: #{inspect(enrollment_id)}"
  end

  @typedoc "Payload for `:enrollment_created` events."
  @type enrollment_created_payload :: %{
          required(:enrollment_id) => String.t(),
          optional(atom()) => term()
        }

  def enrollment_created(enrollment_id, payload \\ %{}, opts \\ [])

  def enrollment_created(enrollment_id, payload, opts) when is_binary(enrollment_id) and byte_size(enrollment_id) > 0 do
    base_payload = %{enrollment_id: enrollment_id}

    IntegrationEvent.new(
      :enrollment_created,
      @source_context,
      :enrollment,
      enrollment_id,
      Map.merge(payload, base_payload),
      opts
    )
  end

  def enrollment_created(enrollment_id, _payload, _opts) do
    raise ArgumentError,
          "enrollment_created/3 requires a non-empty enrollment_id string, got: #{inspect(enrollment_id)}"
  end
end
