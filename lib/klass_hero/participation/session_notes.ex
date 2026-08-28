defmodule KlassHero.Participation.SessionNotes do
  @moduledoc """
  Session notes: the instructor's feedback about one child at one session, and
  the parent's approval of it before it is shared.

  Owns `SessionNote` — submitting, reviewing, revising, the reads each surface
  needs, and the GDPR bulk anonymisation.

  Three different authorization questions live here, and they are deliberately
  not one guard (ADR-0017 states the split):

    * **submit** asks may you act on this session, and as whom — the same
      question as attendance, so it calls `Attendance.authorize_for_record/2`
      rather than restating it.
    * **review** asks is this note about one of your children, of `Family`.
    * **revise** asks are you its author, of the note's own `provider_id`.

  Different authorities, not a duplicated guard.

  Note writes publish through `Notifications` without staging to the outbox:
  they are single-row writes whose events have no registered consumer, and
  `:event_consumers` is the staging filter, so staging them would queue delivery
  work for nobody.
  """

  use KlassHero.Shared.Tracing

  import Ecto.Query

  alias KlassHero.Accounts.Scope
  alias KlassHero.Family
  alias KlassHero.Participation.Attendance
  alias KlassHero.Participation.Events
  alias KlassHero.Participation.Notifications
  alias KlassHero.Participation.ParticipationRecord
  alias KlassHero.Participation.SessionNote
  alias KlassHero.Participation.SessionNoteQueries
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.EctoErrorHelpers
  alias KlassHero.Shared.Adapters.Driven.Persistence.RepositoryHelpers

  require Logger

  @note_update_fields [:content, :status, :rejection_reason, :submitted_at, :reviewed_at]

  # ============================================================================
  # Session notes
  # ============================================================================

  @doc """
  Submits a session note for a participation record, on behalf of `scope`.

  Required params: `participation_record_id`, `content` (max 1000 chars).

  Authorized against the record's session by the same rule as attendance
  (ADR-0017). The authoring provider is derived from the role that authorized the
  write — until #1329 this function took a `provider_id` and stamped it on the note
  without checking it against anything, so any caller could write a note about any
  child in any provider's name.

  Returns `{:ok, note}`, `{:error, :not_found}`, `{:error, :unauthorized}`,
  `{:error, :blank_content}`, `{:error, :invalid_record_status}`, or
  `{:error, :duplicate_note}`.
  """
  @spec submit_session_note(Scope.t(), map()) :: {:ok, SessionNote.t()} | {:error, atom()}
  def submit_session_note(%Scope{} = scope, %{participation_record_id: record_id, content: content}) do
    context_span entity: "session_note" do
      normalized_content = normalize_notes(content)

      with {:content, content} when content != nil <- {:content, normalized_content},
           {:ok, record} <- Attendance.get_participation_record(record_id),
           {:ok, role} <- Attendance.authorize_for_record(scope, record),
           {:ok, provider_id} <- authoring_provider_id(scope, role),
           true <- ParticipationRecord.allows_session_note?(record),
           {:ok, note} <- build_note(record, provider_id, content),
           {:ok, persisted} <- insert_note(note) do
        Notifications.notify(Events.session_note_submitted(persisted))

        {:ok, persisted}
      else
        {:content, nil} -> {:error, :blank_content}
        false -> {:error, :invalid_record_status}
        error -> error
      end
    end
  end

  @doc """
  Reviews a session note (approve or reject), on behalf of `scope`.

  Required params: `note_id`, `decision` (`:approve` or `:reject`). Optional: `reason`.
  The reviewing parent is the scope's, never the caller's to name.

  Returns `{:ok, note}`, `{:error, :not_found}`, `{:error, :unauthorized}`, or
  `{:error, :invalid_decision}`. The parent surface renders both refusals
  identically, so neither confirms a note id it was not given.
  """
  @spec review_session_note(Scope.t(), map()) :: {:ok, SessionNote.t()} | {:error, atom()}
  def review_session_note(%Scope{} = scope, %{note_id: note_id, decision: decision} = params) do
    context_span entity: "session_note" do
      reason = Map.get(params, :reason)

      with {:ok, note} <- fetch_note(note_id),
           :ok <- authorize_note_for_parent(scope, note),
           {:ok, reviewed} <- apply_review_decision(note, decision, reason),
           {:ok, persisted} <- update_note(reviewed) do
        Notifications.notify(review_event(persisted, decision))
        {:ok, persisted}
      end
    end
  end

  @doc """
  Revises a rejected session note with new content, on behalf of `scope`.

  Required params: `note_id`, `content`. The provider is the scope's; a caller
  cannot name the author of the note it is revising.
  """
  @spec revise_session_note(Scope.t(), map()) :: {:ok, SessionNote.t()} | {:error, atom()}
  def revise_session_note(%Scope{} = scope, %{note_id: note_id, content: content}) do
    context_span entity: "session_note" do
      normalized_content = normalize_notes(content)

      with {:content, content} when content != nil <- {:content, normalized_content},
           {:ok, note} <- fetch_note(note_id),
           :ok <- authorize_note_for_author(scope, note),
           {:ok, revised} <- SessionNote.revise(note, content),
           {:ok, persisted} <- update_note(revised) do
        Notifications.notify(Events.session_note_submitted(persisted))

        {:ok, persisted}
      else
        {:content, nil} -> {:error, :blank_content}
        error -> error
      end
    end
  end

  @doc """
  Anonymizes all session notes for a child during GDPR account deletion.

  Replaces note content with "[Removed - account deleted]", clears rejection
  reasons, and sets status to :rejected. Uses bulk update_all for efficiency.

  Returns `{:ok, count}` with the number of notes anonymized.
  """
  def anonymize_session_notes_for_child(child_id) when is_binary(child_id) do
    context_span entity: "session_note" do
      anonymize_notes_for_child(child_id, SessionNote.anonymized_attrs())
    end
  end

  @doc """
  Lists pending session notes for a parent awaiting review.

  Resolved through the parent's children rather than `session_notes.parent_id`,
  which no write path populates — see `parent_child_ids/1`.
  """
  def list_pending_session_notes(parent_id) when is_binary(parent_id) do
    {:ok, parent_id |> parent_child_ids() |> list_notes_pending_for_children()}
  end

  @doc "Gets approved session notes for a child."
  def get_approved_session_notes(child_id) when is_binary(child_id) do
    {:ok, list_notes_approved_by_child(child_id)}
  end

  @doc "Gets a session note by participation record and provider. Returns `{:ok, note}` or `{:error, :not_found}`."
  def get_session_note_by_record_and_provider(record_id, provider_id)
      when is_binary(record_id) and is_binary(provider_id) do
    fetch_note_by_record_and_provider(record_id, provider_id)
  end

  @doc """
  Lists session notes for multiple participation records by a single provider.

  Returns a flat list of notes. Use this instead of calling
  `get_session_note_by_record_and_provider/2` per record to avoid N+1 queries.
  """
  def list_session_notes_by_records_and_provider(record_ids, provider_id)
      when is_list(record_ids) and is_binary(provider_id) do
    list_notes_by_records_and_provider(record_ids, provider_id)
  end

  # Which provider a note is written in the name of. Derived from the role that
  # already authorized the write, so the two can never disagree; an admin holds no
  # provider identity and a Session Note is the Instructor's, so admin is refused
  # here even though `authorize_for_record/2` granted the write.
  defp authoring_provider_id(%Scope{provider: %{id: id}}, :provider), do: {:ok, id}
  defp authoring_provider_id(%Scope{staff_member: %{provider_id: id}}, :staff), do: {:ok, id}
  defp authoring_provider_id(%Scope{}, _role), do: {:error, :unauthorized}

  # A note is the parent's to review when it is about one of their children.
  # `session_notes.parent_id` is not consulted: no write path populates it (#1329).
  defp authorize_note_for_parent(%Scope{parent: %{id: parent_id}}, %SessionNote{child_id: child_id}) do
    if child_id in parent_child_ids(parent_id), do: :ok, else: {:error, :unauthorized}
  end

  defp authorize_note_for_parent(%Scope{}, %SessionNote{}), do: {:error, :unauthorized}

  # Revision is the author's alone — not the employing provider's, and not another
  # staff member's on the same session.
  defp authorize_note_for_author(%Scope{provider: %{id: id}}, %SessionNote{provider_id: id}), do: :ok

  defp authorize_note_for_author(%Scope{staff_member: %{provider_id: id}}, %SessionNote{provider_id: id}), do: :ok

  defp authorize_note_for_author(%Scope{}, %SessionNote{}), do: {:error, :unauthorized}

  defp build_note(record, provider_id, content) do
    SessionNote.new(%{
      id: Ecto.UUID.generate(),
      participation_record_id: record.id,
      child_id: record.child_id,
      # `parent_id` is deliberately not set. `participation_records.parent_id` is
      # NULL on every row the runtime seeds, so copying it here wrote NULL and made
      # a dead column look alive — which is what hid #1329. Ownership is asked of
      # Family, through the child.
      provider_id: provider_id,
      content: content
    })
  end

  defp apply_review_decision(note, :approve, _reason), do: SessionNote.approve(note)
  defp apply_review_decision(note, :reject, reason), do: SessionNote.reject(note, reason)
  defp apply_review_decision(_note, _decision, _reason), do: {:error, :invalid_decision}

  @doc false
  def normalize_notes(nil), do: nil

  def normalize_notes(notes) when is_binary(notes) do
    case String.trim(notes) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp review_event(note, :approve), do: Events.session_note_approved(note)
  defp review_event(note, :reject), do: Events.session_note_rejected(note)

  # ============================================================================
  # Persistence — session notes
  # ============================================================================

  defp insert_note(%SessionNote{} = note) do
    note
    |> Map.from_struct()
    |> SessionNote.create_changeset()
    |> Repo.insert()
    |> handle_note_insert()
  end

  defp update_note(%SessionNote{} = note) do
    case Repo.get(SessionNote, note.id) do
      nil ->
        {:error, :not_found}

      schema ->
        attrs = Map.take(note, @note_update_fields)

        schema
        |> SessionNote.update_changeset(attrs)
        |> Repo.update()
        |> handle_note_update()
    end
  end

  # Family owns the child→guardian relation, so it is asked rather than copied
  # (ADR-0015). A parent with no children yields an empty list, which every caller
  # below treats as "owns nothing" rather than "no filter".
  defp parent_child_ids(parent_id) do
    parent_id
    |> Family.get_child_ids_for_parent()
    |> MapSet.to_list()
  end

  defp list_notes_pending_for_children([]), do: []

  defp list_notes_pending_for_children(child_ids) do
    SessionNoteQueries.base()
    |> SessionNoteQueries.by_children(child_ids)
    |> SessionNoteQueries.pending()
    |> SessionNoteQueries.order_by_submitted_desc()
    |> Repo.all()
  end

  defp list_notes_approved_by_child(child_id) do
    SessionNoteQueries.base()
    |> SessionNoteQueries.by_child(child_id)
    |> SessionNoteQueries.approved()
    |> SessionNoteQueries.order_by_submitted_desc()
    |> Repo.all()
  end

  @doc """
  Approved notes for the given children, grouped by child id.

  Public for the roster reads, which show a child's approved notes alongside
  their attendance.
  """
  @spec list_approved_notes_for_children([String.t()]) :: %{optional(String.t()) => [SessionNote.t()]}
  def list_approved_notes_for_children(child_ids) do
    SessionNoteQueries.base()
    |> SessionNoteQueries.approved()
    |> where([note: n], n.child_id in ^child_ids)
    |> SessionNoteQueries.order_by_submitted_desc()
    |> Repo.all()
    |> Enum.group_by(& &1.child_id)
  end

  defp list_notes_by_records_and_provider(record_ids, provider_id) do
    SessionNoteQueries.base()
    |> SessionNoteQueries.by_participation_records(record_ids)
    |> SessionNoteQueries.by_provider(provider_id)
    |> Repo.all()
  end

  defp fetch_note(id) when is_binary(id) do
    RepositoryHelpers.get_schema_by_uuid(SessionNote, id)
  end

  defp fetch_note_by_record_and_provider(record_id, provider_id) do
    SessionNoteQueries.base()
    |> SessionNoteQueries.by_participation_record(record_id)
    |> SessionNoteQueries.by_provider(provider_id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      schema -> {:ok, schema}
    end
  end

  defp anonymize_notes_for_child(child_id, anonymized_attrs) when is_binary(child_id) and is_map(anonymized_attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # update_all bypasses Ecto.Enum casting — convert :status atom to string manually.
    set_fields =
      anonymized_attrs
      |> convert_note_enum_fields()
      |> Enum.to_list()
      |> Keyword.new()
      |> Keyword.put(:updated_at, now)

    {count, _} =
      SessionNote
      |> where([n], n.child_id == ^child_id)
      |> Repo.update_all(set: set_fields)

    {:ok, count}
  end

  defp handle_note_insert({:ok, schema}), do: {:ok, schema}

  defp handle_note_insert({:error, %Ecto.Changeset{errors: errors} = changeset}) do
    if EctoErrorHelpers.any_unique_constraint_violation?(errors) do
      {:error, :duplicate_note}
    else
      Logger.warning("[Participation] Session note validation failed on insert",
        errors: inspect(changeset.errors)
      )

      {:error, :validation_failed}
    end
  end

  defp handle_note_update({:ok, schema}), do: {:ok, schema}

  defp handle_note_update({:error, %Ecto.Changeset{} = changeset}) do
    Logger.warning("[Participation] Session note validation failed on update",
      errors: inspect(changeset.errors)
    )

    {:error, :validation_failed}
  end

  defp convert_note_enum_fields(attrs) do
    Map.update(attrs, :status, nil, fn
      value when is_atom(value) and not is_nil(value) -> to_string(value)
      value -> value
    end)
  end
end
