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

  @aggregate_type :participation

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

    DomainEvent.new(:session_created, session.id, @aggregate_type, payload, opts)
  end

  @doc "Creates a session_started event."
  @spec session_started(ProgramSession.t(), keyword()) :: DomainEvent.t()
  def session_started(%ProgramSession{} = session, opts \\ []) do
    payload = %{
      session_id: session.id,
      program_id: session.program_id,
      started_at: DateTime.utc_now()
    }

    DomainEvent.new(:session_started, session.id, @aggregate_type, payload, opts)
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

    DomainEvent.new(:session_completed, session.id, @aggregate_type, payload, event_opts)
  end

  @doc "Creates a roster_seeded event."
  @spec roster_seeded(String.t(), String.t(), non_neg_integer(), keyword()) :: DomainEvent.t()
  def roster_seeded(session_id, program_id, count, opts \\ []) when is_binary(session_id) and is_binary(program_id) do
    payload = %{
      session_id: session_id,
      program_id: program_id,
      seeded_count: count
    }

    DomainEvent.new(:roster_seeded, session_id, @aggregate_type, payload, opts)
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

    DomainEvent.new(:child_checked_in, record.id, @aggregate_type, payload, opts)
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

    DomainEvent.new(:child_checked_in, record.id, @aggregate_type, payload, [])
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

    DomainEvent.new(:child_checked_out, record.id, @aggregate_type, payload, opts)
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

    DomainEvent.new(:child_checked_out, record.id, @aggregate_type, payload, [])
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

    DomainEvent.new(:child_marked_absent, record.id, @aggregate_type, payload, opts)
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

    DomainEvent.new(:child_marked_absent, record.id, @aggregate_type, payload, [])
  end

  @doc "Creates a session_note_submitted event."
  @spec session_note_submitted(SessionNote.t(), keyword()) :: DomainEvent.t()
  def session_note_submitted(%SessionNote{} = note, opts \\ []) do
    payload = session_note_payload(note)

    DomainEvent.new(:session_note_submitted, note.id, :session_note, payload, opts)
  end

  @doc "Creates a session_note_approved event."
  @spec session_note_approved(SessionNote.t(), keyword()) :: DomainEvent.t()
  def session_note_approved(%SessionNote{} = note, opts \\ []) do
    payload = session_note_payload(note)

    DomainEvent.new(:session_note_approved, note.id, :session_note, payload, opts)
  end

  @doc "Creates a session_note_rejected event."
  @spec session_note_rejected(SessionNote.t(), keyword()) :: DomainEvent.t()
  def session_note_rejected(%SessionNote{} = note, opts \\ []) do
    payload = session_note_payload(note)

    DomainEvent.new(:session_note_rejected, note.id, :session_note, payload, opts)
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
