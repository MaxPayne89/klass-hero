defmodule KlassHero.Participation.Domain.Events.ParticipationEvents do
  @moduledoc """
  Factory module for creating participation domain events.

  ## Event Types

  - `session_created` - A new program session was created
  - `session_started` - A session has begun
  - `session_completed` - A session has ended
  - `roster_seeded` - Participation records were bulk-seeded for a session
  - `child_checked_in` - A child was checked into a session
  - `child_checked_out` - A child was checked out of a session
  - `child_marked_absent` - A child was marked absent from a session
  - `session_note_submitted` - A session note was submitted for review
  - `session_note_approved` - A session note was approved by a parent
  - `session_note_rejected` - A session note was rejected by a parent

  All events are returned as `DomainEvent` structs.
  """

  alias KlassHero.Participation.ParticipationRecord
  alias KlassHero.Participation.ProgramSession
  alias KlassHero.Participation.SessionNote
  alias KlassHero.Shared.Domain.Events.DomainEvent

  @type session_note_payload :: %{
          note_id: String.t(),
          participation_record_id: String.t(),
          child_id: String.t(),
          provider_id: String.t(),
          parent_id: String.t() | nil
        }

  # Single source of truth for event routing (#1108). Each event's aggregate_type
  # is looked up here rather than hand-written at each call site, and subscription
  # topics on the `Participation` facade derive from the same map — so renaming an
  # atom moves the publisher and every LiveView subscriber together.
  @event_aggregates %{
    session_created: :participation,
    session_started: :participation,
    session_completed: :participation,
    roster_seeded: :participation,
    child_checked_in: :participation,
    child_checked_out: :participation,
    child_marked_absent: :participation,
    session_note_submitted: :session_note,
    session_note_approved: :session_note,
    session_note_rejected: :session_note
  }

  # The event_types each LiveView group subscribes to. Kept alongside the registry
  # so the facade can build the exact topic strings subscribers need.
  @subscription_groups %{
    attendance: [:child_checked_in, :child_checked_out, :child_marked_absent],
    session_note: [:session_note_submitted, :session_note_approved, :session_note_rejected]
  }

  @doc "Returns the aggregate_type registered for an event type. Raises if unknown."
  @spec aggregate_type_for(atom()) :: atom()
  def aggregate_type_for(event_type), do: Map.fetch!(@event_aggregates, event_type)

  @doc "Returns the ordered event types a subscription group listens for."
  @spec subscription_event_types(atom()) :: [atom()]
  def subscription_event_types(group), do: Map.fetch!(@subscription_groups, group)

  @doc "Creates a session_created event."
  @spec session_created(ProgramSession.t(), keyword()) :: DomainEvent.t()
  def session_created(%ProgramSession{} = session, opts \\ []) do
    payload = %{
      session_id: session.id,
      program_id: session.program_id,
      session_date: session.session_date,
      start_time: session.start_time,
      end_time: session.end_time,
      location: session.location,
      max_capacity: session.max_capacity
    }

    new_event(:session_created, session.id, payload, opts)
  end

  @doc "Creates a session_started event."
  @spec session_started(ProgramSession.t(), keyword()) :: DomainEvent.t()
  def session_started(%ProgramSession{} = session, opts \\ []) do
    payload = %{
      session_id: session.id,
      program_id: session.program_id,
      started_at: DateTime.utc_now()
    }

    new_event(:session_started, session.id, payload, opts)
  end

  @doc "Creates a session_completed event."
  @spec session_completed(ProgramSession.t(), keyword()) :: DomainEvent.t()
  def session_completed(%ProgramSession{} = session, opts \\ []) do
    {extra, event_opts} = Keyword.pop(opts, :extra_payload, %{})

    base_payload = %{
      session_id: session.id,
      program_id: session.program_id,
      completed_at: DateTime.utc_now()
    }

    payload = Map.merge(extra, base_payload)

    new_event(:session_completed, session.id, payload, event_opts)
  end

  @doc "Creates a roster_seeded event."
  @spec roster_seeded(String.t(), String.t(), non_neg_integer(), keyword()) :: DomainEvent.t()
  def roster_seeded(session_id, program_id, count, opts \\ []) when is_binary(session_id) and is_binary(program_id) do
    payload = %{
      session_id: session_id,
      program_id: program_id,
      seeded_count: count
    }

    new_event(:roster_seeded, session_id, payload, opts)
  end

  @doc deprecated: "Use child_checked_in/2 with ProgramSession to include program_id in payload"
  @spec child_checked_in(ParticipationRecord.t()) :: DomainEvent.t()
  def child_checked_in(%ParticipationRecord{} = record) do
    child_checked_in(record, [])
  end

  @spec child_checked_in(ParticipationRecord.t(), keyword()) :: DomainEvent.t()
  def child_checked_in(%ParticipationRecord{} = record, opts) when is_list(opts) do
    payload = %{
      record_id: record.id,
      session_id: record.session_id,
      child_id: record.child_id,
      checked_in_by: record.check_in_by,
      checked_in_at: record.check_in_at,
      notes: record.check_in_notes
    }

    new_event(:child_checked_in, record.id, payload, opts)
  end

  def child_checked_in(%ParticipationRecord{} = record, nil), do: child_checked_in(record, [])

  @doc "Creates a child_checked_in event with program_id from the session."
  @spec child_checked_in(ParticipationRecord.t(), ProgramSession.t()) :: DomainEvent.t()
  def child_checked_in(%ParticipationRecord{} = record, %ProgramSession{} = session) do
    payload = %{
      record_id: record.id,
      session_id: record.session_id,
      child_id: record.child_id,
      checked_in_by: record.check_in_by,
      checked_in_at: record.check_in_at,
      notes: record.check_in_notes,
      # program_id from session enables NotifyLiveViews to route PubSub broadcasts per provider.
      program_id: session.program_id
    }

    new_event(:child_checked_in, record.id, payload, [])
  end

  @doc deprecated: "Use child_checked_out/2 with ProgramSession to include program_id in payload"
  @spec child_checked_out(ParticipationRecord.t()) :: DomainEvent.t()
  def child_checked_out(%ParticipationRecord{} = record) do
    child_checked_out(record, [])
  end

  @spec child_checked_out(ParticipationRecord.t(), keyword()) :: DomainEvent.t()
  def child_checked_out(%ParticipationRecord{} = record, opts) when is_list(opts) do
    payload = %{
      record_id: record.id,
      session_id: record.session_id,
      child_id: record.child_id,
      checked_out_by: record.check_out_by,
      checked_out_at: record.check_out_at,
      notes: record.check_out_notes
    }

    new_event(:child_checked_out, record.id, payload, opts)
  end

  def child_checked_out(%ParticipationRecord{} = record, nil), do: child_checked_out(record, [])

  @doc "Creates a child_checked_out event with program_id from the session."
  @spec child_checked_out(ParticipationRecord.t(), ProgramSession.t()) :: DomainEvent.t()
  def child_checked_out(%ParticipationRecord{} = record, %ProgramSession{} = session) do
    payload = %{
      record_id: record.id,
      session_id: record.session_id,
      child_id: record.child_id,
      checked_out_by: record.check_out_by,
      checked_out_at: record.check_out_at,
      notes: record.check_out_notes,
      program_id: session.program_id
    }

    new_event(:child_checked_out, record.id, payload, [])
  end

  @doc deprecated: "Use child_marked_absent/2 with ProgramSession to include program_id in payload"
  @spec child_marked_absent(ParticipationRecord.t()) :: DomainEvent.t()
  def child_marked_absent(%ParticipationRecord{} = record) do
    child_marked_absent(record, [])
  end

  @spec child_marked_absent(ParticipationRecord.t(), keyword()) :: DomainEvent.t()
  def child_marked_absent(%ParticipationRecord{} = record, opts) when is_list(opts) do
    payload = %{
      record_id: record.id,
      session_id: record.session_id,
      child_id: record.child_id
    }

    new_event(:child_marked_absent, record.id, payload, opts)
  end

  def child_marked_absent(%ParticipationRecord{} = record, nil), do: child_marked_absent(record, [])

  @doc "Creates a child_marked_absent event with program_id from the session."
  @spec child_marked_absent(ParticipationRecord.t(), ProgramSession.t()) :: DomainEvent.t()
  def child_marked_absent(%ParticipationRecord{} = record, %ProgramSession{} = session) do
    payload = %{
      record_id: record.id,
      session_id: record.session_id,
      child_id: record.child_id,
      program_id: session.program_id
    }

    new_event(:child_marked_absent, record.id, payload, [])
  end

  @doc "Creates a session_note_submitted event."
  @spec session_note_submitted(SessionNote.t(), keyword()) :: DomainEvent.t()
  def session_note_submitted(%SessionNote{} = note, opts \\ []) do
    payload = session_note_payload(note)

    new_event(:session_note_submitted, note.id, payload, opts)
  end

  @doc "Creates a session_note_approved event."
  @spec session_note_approved(SessionNote.t(), keyword()) :: DomainEvent.t()
  def session_note_approved(%SessionNote{} = note, opts \\ []) do
    payload = session_note_payload(note)

    new_event(:session_note_approved, note.id, payload, opts)
  end

  @doc "Creates a session_note_rejected event."
  @spec session_note_rejected(SessionNote.t(), keyword()) :: DomainEvent.t()
  def session_note_rejected(%SessionNote{} = note, opts \\ []) do
    payload = session_note_payload(note)

    new_event(:session_note_rejected, note.id, payload, opts)
  end

  # Builds a DomainEvent, deriving aggregate_type from the registry so no call site
  # hand-writes it (#1108).
  @spec new_event(atom(), String.t(), map(), keyword()) :: DomainEvent.t()
  defp new_event(event_type, aggregate_id, payload, opts) do
    DomainEvent.new(event_type, aggregate_id, aggregate_type_for(event_type), payload, opts)
  end

  @spec session_note_payload(SessionNote.t()) :: session_note_payload()
  defp session_note_payload(%SessionNote{} = note) do
    %{
      note_id: note.id,
      participation_record_id: note.participation_record_id,
      child_id: note.child_id,
      provider_id: note.provider_id,
      parent_id: note.parent_id
    }
  end
end
