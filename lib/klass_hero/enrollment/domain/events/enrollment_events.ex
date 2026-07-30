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
