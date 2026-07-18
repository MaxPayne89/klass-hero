defmodule KlassHero.Participation.Domain.Events.ParticipationIntegrationEvents do
  @moduledoc """
  Factory module for creating Participation context integration events.

  Integration events are the public contract between bounded contexts.
  They carry stable, versioned payloads with only primitive types.

  ## Events

  - `:session_created` - Emitted when a new session is scheduled.
    Entity type: `:session`.
  - `:session_started` - Emitted when a session begins (instructor opens it).
    Entity type: `:session`.
  - `:session_completed` - Emitted when a session ends (all check-outs done).
    Entity type: `:session`.
  - `:session_cancelled` - Emitted when a session is cancelled (e.g. provider cancels a scheduled session).
    Entity type: `:session`.
  - `:roster_seeded` - Emitted after participation records are bulk-seeded for a session.
    Entity type: `:session`.
  - `:child_checked_in` - Emitted when a child is checked into a session.
    Entity type: `:participation_record`.
  - `:child_checked_out` - Emitted when a child is checked out of a session.
    Entity type: `:participation_record`.
  - `:child_marked_absent` - Emitted when a child is marked absent for a session.
    Entity type: `:participation_record`.
  - `:session_note_submitted` - Emitted when a session note is submitted for review.
    Entity type: `:session_note`.
  - `:session_note_approved` - Emitted when a session note is approved.
    Entity type: `:session_note`.
  - `:session_note_rejected` - Emitted when a session note is rejected.
    Entity type: `:session_note`.
  """

  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  @typedoc "Payload for `:session_created` events."
  @type session_created_payload :: %{
          required(:session_id) => String.t(),
          required(:program_id) => String.t(),
          required(:session_date) => Date.t(),
          required(:start_time) => Time.t(),
          required(:end_time) => Time.t(),
          optional(atom()) => term()
        }

  @typedoc "Payload for `:session_started` events."
  @type session_started_payload :: %{
          required(:session_id) => String.t(),
          required(:program_id) => String.t(),
          optional(atom()) => term()
        }

  @typedoc "Payload for `:session_completed` events."
  @type session_completed_payload :: %{
          required(:session_id) => String.t(),
          required(:program_id) => String.t(),
          required(:provider_id) => String.t(),
          required(:program_title) => String.t(),
          optional(atom()) => term()
        }

  @typedoc "Payload for `:roster_seeded` events."
  @type roster_seeded_payload :: %{
          required(:session_id) => String.t(),
          required(:program_id) => String.t(),
          required(:seeded_count) => non_neg_integer()
        }

  @typedoc "Payload for `:child_checked_in` events."
  @type child_checked_in_payload :: %{
          required(:record_id) => String.t(),
          required(:session_id) => String.t(),
          required(:child_id) => String.t(),
          optional(atom()) => term()
        }

  @typedoc "Payload for `:child_checked_out` events."
  @type child_checked_out_payload :: %{
          required(:record_id) => String.t(),
          required(:session_id) => String.t(),
          required(:child_id) => String.t(),
          optional(atom()) => term()
        }

  @typedoc "Payload for `:child_marked_absent` events."
  @type child_marked_absent_payload :: %{
          required(:record_id) => String.t(),
          required(:session_id) => String.t(),
          required(:child_id) => String.t(),
          optional(atom()) => term()
        }

  @typedoc "Payload for `:session_note_submitted` events."
  @type session_note_submitted_payload :: %{
          required(:note_id) => String.t(),
          required(:participation_record_id) => String.t(),
          required(:child_id) => String.t(),
          required(:provider_id) => String.t(),
          optional(atom()) => term()
        }

  @typedoc "Payload for `:session_note_approved` events."
  @type session_note_approved_payload :: %{
          required(:note_id) => String.t(),
          required(:participation_record_id) => String.t(),
          required(:child_id) => String.t(),
          required(:provider_id) => String.t(),
          optional(atom()) => term()
        }

  @typedoc "Payload for `:session_note_rejected` events."
  @type session_note_rejected_payload :: %{
          required(:note_id) => String.t(),
          required(:participation_record_id) => String.t(),
          required(:child_id) => String.t(),
          required(:provider_id) => String.t(),
          optional(atom()) => term()
        }

  @source_context :participation

  @doc "Creates a `session_created` integration event. Raises `ArgumentError` on invalid args."
  def session_created(session_id, payload \\ %{}, opts \\ [])

  def session_created(session_id, %{program_id: _, session_date: _, start_time: _, end_time: _} = payload, opts)
      when is_binary(session_id) and byte_size(session_id) > 0 do
    base_payload = %{session_id: session_id}

    IntegrationEvent.new(
      :session_created,
      @source_context,
      :session,
      session_id,
      # base_payload wins: Map.merge puts the second arg's keys last, overriding any :session_id in payload.
      Map.merge(payload, base_payload),
      opts
    )
  end

  def session_created(session_id, payload, _opts) when is_binary(session_id) and byte_size(session_id) > 0 do
    missing = [:program_id, :session_date, :start_time, :end_time] -- Map.keys(payload)

    raise ArgumentError,
          "session_created missing required payload keys: #{inspect(missing)}"
  end

  def session_created(session_id, _payload, _opts) do
    raise ArgumentError,
          "session_created/3 requires a non-empty session_id string, got: #{inspect(session_id)}"
  end

  @doc "Creates a `session_started` integration event. Raises `ArgumentError` on invalid args."
  def session_started(session_id, payload \\ %{}, opts \\ [])

  def session_started(session_id, %{program_id: _} = payload, opts)
      when is_binary(session_id) and byte_size(session_id) > 0 do
    base_payload = %{session_id: session_id}

    IntegrationEvent.new(
      :session_started,
      @source_context,
      :session,
      session_id,
      Map.merge(payload, base_payload),
      opts
    )
  end

  def session_started(session_id, payload, _opts) when is_binary(session_id) and byte_size(session_id) > 0 do
    missing = [:program_id] -- Map.keys(payload)

    raise ArgumentError,
          "session_started missing required payload keys: #{inspect(missing)}"
  end

  def session_started(session_id, _payload, _opts) do
    raise ArgumentError,
          "session_started/3 requires a non-empty session_id string, got: #{inspect(session_id)}"
  end

  @doc "Creates a `session_completed` integration event. Raises `ArgumentError` on invalid args."
  def session_completed(session_id, payload \\ %{}, opts \\ [])

  def session_completed(session_id, %{program_id: _, provider_id: _, program_title: _} = payload, opts)
      when is_binary(session_id) and byte_size(session_id) > 0 do
    base_payload = %{session_id: session_id}

    IntegrationEvent.new(
      :session_completed,
      @source_context,
      :session,
      session_id,
      Map.merge(payload, base_payload),
      opts
    )
  end

  def session_completed(session_id, payload, _opts) when is_binary(session_id) and byte_size(session_id) > 0 do
    missing = [:program_id, :provider_id, :program_title] -- Map.keys(payload)

    raise ArgumentError,
          "session_completed missing required payload keys: #{inspect(missing)}"
  end

  def session_completed(session_id, _payload, _opts) do
    raise ArgumentError,
          "session_completed/3 requires a non-empty session_id string, got: #{inspect(session_id)}"
  end

  @doc "Creates a `roster_seeded` integration event."
  def roster_seeded(session_id, payload \\ %{}, opts \\ [])

  def roster_seeded(session_id, %{program_id: _, seeded_count: _} = payload, opts)
      when is_binary(session_id) and byte_size(session_id) > 0 do
    base_payload = %{session_id: session_id}

    IntegrationEvent.new(
      :roster_seeded,
      @source_context,
      :session,
      session_id,
      Map.merge(payload, base_payload),
      opts
    )
  end

  def roster_seeded(session_id, payload, _opts) when is_binary(session_id) and byte_size(session_id) > 0 do
    missing = [:program_id, :seeded_count] -- Map.keys(payload)

    raise ArgumentError,
          "roster_seeded missing required payload keys: #{inspect(missing)}"
  end

  def roster_seeded(session_id, _payload, _opts) do
    raise ArgumentError,
          "roster_seeded/3 requires a non-empty session_id string, got: #{inspect(session_id)}"
  end

  @doc "Creates a `child_checked_in` integration event. Raises `ArgumentError` on invalid args."
  def child_checked_in(record_id, payload \\ %{}, opts \\ [])

  def child_checked_in(record_id, %{session_id: _, child_id: _} = payload, opts)
      when is_binary(record_id) and byte_size(record_id) > 0 do
    base_payload = %{record_id: record_id}

    IntegrationEvent.new(
      :child_checked_in,
      @source_context,
      :participation_record,
      record_id,
      Map.merge(payload, base_payload),
      opts
    )
  end

  def child_checked_in(record_id, payload, _opts) when is_binary(record_id) and byte_size(record_id) > 0 do
    missing = [:session_id, :child_id] -- Map.keys(payload)

    raise ArgumentError,
          "child_checked_in missing required payload keys: #{inspect(missing)}"
  end

  def child_checked_in(record_id, _payload, _opts) do
    raise ArgumentError,
          "child_checked_in/3 requires a non-empty record_id string, got: #{inspect(record_id)}"
  end

  @doc "Creates a `child_checked_out` integration event. Raises `ArgumentError` on invalid args."
  def child_checked_out(record_id, payload \\ %{}, opts \\ [])

  def child_checked_out(record_id, %{session_id: _, child_id: _} = payload, opts)
      when is_binary(record_id) and byte_size(record_id) > 0 do
    base_payload = %{record_id: record_id}

    IntegrationEvent.new(
      :child_checked_out,
      @source_context,
      :participation_record,
      record_id,
      Map.merge(payload, base_payload),
      opts
    )
  end

  def child_checked_out(record_id, payload, _opts) when is_binary(record_id) and byte_size(record_id) > 0 do
    missing = [:session_id, :child_id] -- Map.keys(payload)

    raise ArgumentError,
          "child_checked_out missing required payload keys: #{inspect(missing)}"
  end

  def child_checked_out(record_id, _payload, _opts) do
    raise ArgumentError,
          "child_checked_out/3 requires a non-empty record_id string, got: #{inspect(record_id)}"
  end

  @doc "Creates a `child_marked_absent` integration event. Raises `ArgumentError` on invalid args."
  def child_marked_absent(record_id, payload \\ %{}, opts \\ [])

  def child_marked_absent(record_id, %{session_id: _, child_id: _} = payload, opts)
      when is_binary(record_id) and byte_size(record_id) > 0 do
    base_payload = %{record_id: record_id}

    IntegrationEvent.new(
      :child_marked_absent,
      @source_context,
      :participation_record,
      record_id,
      Map.merge(payload, base_payload),
      opts
    )
  end

  def child_marked_absent(record_id, payload, _opts) when is_binary(record_id) and byte_size(record_id) > 0 do
    missing = [:session_id, :child_id] -- Map.keys(payload)

    raise ArgumentError,
          "child_marked_absent missing required payload keys: #{inspect(missing)}"
  end

  def child_marked_absent(record_id, _payload, _opts) do
    raise ArgumentError,
          "child_marked_absent/3 requires a non-empty record_id string, got: #{inspect(record_id)}"
  end

  @doc "Creates a `session_note_submitted` integration event. Raises `ArgumentError` on invalid args."
  def session_note_submitted(note_id, payload \\ %{}, opts \\ [])

  def session_note_submitted(note_id, %{participation_record_id: _, child_id: _, provider_id: _} = payload, opts)
      when is_binary(note_id) and byte_size(note_id) > 0 do
    base_payload = %{note_id: note_id}

    IntegrationEvent.new(
      :session_note_submitted,
      @source_context,
      :session_note,
      note_id,
      Map.merge(payload, base_payload),
      opts
    )
  end

  def session_note_submitted(note_id, payload, _opts) when is_binary(note_id) and byte_size(note_id) > 0 do
    missing = [:participation_record_id, :child_id, :provider_id] -- Map.keys(payload)

    raise ArgumentError,
          "session_note_submitted missing required payload keys: #{inspect(missing)}"
  end

  def session_note_submitted(note_id, _payload, _opts) do
    raise ArgumentError,
          "session_note_submitted/3 requires a non-empty note_id string, got: #{inspect(note_id)}"
  end

  @doc "Creates a `session_note_approved` integration event. Raises `ArgumentError` on invalid args."
  def session_note_approved(note_id, payload \\ %{}, opts \\ [])

  def session_note_approved(note_id, %{participation_record_id: _, child_id: _, provider_id: _} = payload, opts)
      when is_binary(note_id) and byte_size(note_id) > 0 do
    base_payload = %{note_id: note_id}

    IntegrationEvent.new(
      :session_note_approved,
      @source_context,
      :session_note,
      note_id,
      Map.merge(payload, base_payload),
      opts
    )
  end

  def session_note_approved(note_id, payload, _opts) when is_binary(note_id) and byte_size(note_id) > 0 do
    missing = [:participation_record_id, :child_id, :provider_id] -- Map.keys(payload)

    raise ArgumentError,
          "session_note_approved missing required payload keys: #{inspect(missing)}"
  end

  def session_note_approved(note_id, _payload, _opts) do
    raise ArgumentError,
          "session_note_approved/3 requires a non-empty note_id string, got: #{inspect(note_id)}"
  end

  @doc "Creates a `session_note_rejected` integration event. Raises `ArgumentError` on invalid args."
  def session_note_rejected(note_id, payload \\ %{}, opts \\ [])

  def session_note_rejected(note_id, %{participation_record_id: _, child_id: _, provider_id: _} = payload, opts)
      when is_binary(note_id) and byte_size(note_id) > 0 do
    base_payload = %{note_id: note_id}

    IntegrationEvent.new(
      :session_note_rejected,
      @source_context,
      :session_note,
      note_id,
      Map.merge(payload, base_payload),
      opts
    )
  end

  def session_note_rejected(note_id, payload, _opts) when is_binary(note_id) and byte_size(note_id) > 0 do
    missing = [:participation_record_id, :child_id, :provider_id] -- Map.keys(payload)

    raise ArgumentError,
          "session_note_rejected missing required payload keys: #{inspect(missing)}"
  end

  def session_note_rejected(note_id, _payload, _opts) do
    raise ArgumentError,
          "session_note_rejected/3 requires a non-empty note_id string, got: #{inspect(note_id)}"
  end

  @typedoc "Payload for `:session_cancelled` events."
  @type session_cancelled_payload :: %{
          required(:session_id) => String.t(),
          required(:program_id) => String.t(),
          optional(atom()) => term()
        }

  @doc """
  Creates a `session_cancelled` integration event.

  Published when a session is cancelled (e.g. provider cancels a scheduled session).
  """
  def session_cancelled(session_id, payload \\ %{}, opts \\ [])

  def session_cancelled(session_id, %{program_id: _} = payload, opts)
      when is_binary(session_id) and byte_size(session_id) > 0 do
    base_payload = %{session_id: session_id}

    IntegrationEvent.new(
      :session_cancelled,
      @source_context,
      :session,
      session_id,
      Map.merge(payload, base_payload),
      opts
    )
  end

  def session_cancelled(session_id, payload, _opts) when is_binary(session_id) and byte_size(session_id) > 0 do
    missing = [:program_id] -- Map.keys(payload)

    raise ArgumentError,
          "session_cancelled missing required payload keys: #{inspect(missing)}"
  end

  def session_cancelled(session_id, _payload, _opts) do
    raise ArgumentError,
          "session_cancelled/3 requires a non-empty session_id string, got: #{inspect(session_id)}"
  end
end
