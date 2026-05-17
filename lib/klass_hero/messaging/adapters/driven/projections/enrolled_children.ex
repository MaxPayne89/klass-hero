defmodule KlassHero.Messaging.Adapters.Driven.Projections.EnrolledChildren do
  @moduledoc """
  Event-driven projection maintaining the `messaging_enrolled_children` read table.

  Mirrors the enrolment + child + parent context needed for Messaging features so
  that conversation summaries can display which child(ren) a conversation is about
  without joining across context boundaries.

  Built on `KlassHero.Shared.Projection` (base) + `Projection.WithBootstrapRetry`
  (linear-backoff retry on transient bootstrap failure).

  ## Event handling

  - `:enrollment_created` — inserts enrollment row(s)
  - `:enrollment_cancelled` — deletes rows for that enrollment
  - `:child_created` — updates child_first_name across rows
  - `:child_updated` — updates child_first_name across rows
  - `:conversation_created` — broadcasts `:enrolled_children_changed` domain event for downstream projections

  After every state-changing operation, emits a `:enrolled_children_changed`
  domain event so dependent projections (ConversationSummaries) can refresh.

  ## Cross-Context Coupling

  Two paths in this module query Enrollment/Family tables directly via raw
  string names:

  - `bootstrap_from_write_tables/0` joins `enrollments`, `children`, and
    `parents` to recover from a cold start where the read table is empty but
    write tables already contain data (e.g. after seeding or a projection reset).
  - `resolve_child_first_name/1` (called by `project_enrollment_created/1`)
    looks up `children.first_name` because the `enrollment_created` integration
    event payload does not carry the child's name.

  These are **pragmatic cross-context couplings** at the adapter layer: raw
  string table references (rather than schema-module aliases) sidestep
  Boundary's compile-time isolation, but Messaging still gains runtime
  knowledge of Enrollment's and Family's physical schema — a rename in those
  contexts will silently break these paths.

  Both paths mirror the precedent set by
  `Family.Adapters.Driven.ACL.ChildEnrollmentACL` and
  `Enrollment.Adapters.Driven.ACL.ProgramCatalogACL`, which adopt the same
  raw-string workaround to avoid hard Boundary dependencies. Issue #685
  tracks replacing all of these with dedicated cross-context ports.
  """

  use KlassHero.Shared.Projection,
    topics: [
      "integration:enrollment:enrollment_created",
      "integration:enrollment:enrollment_cancelled",
      "integration:family:child_created",
      "integration:family:child_updated",
      "integration:messaging:conversation_created"
    ]

  use KlassHero.Shared.Projection.WithBootstrapRetry

  import Ecto.Query

  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.ConversationSummarySchema
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.EnrolledChildrenSchema
  alias KlassHero.Repo
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.Domain.Events.IntegrationEvent
  alias KlassHero.Shared.Projection

  @enrolled_children_changed_topic "messaging:enrolled_children_changed"

  # Behaviour callbacks ───────────────────────────────────────────────────────

  @impl Projection
  def bootstrap_impl, do: bootstrap_from_write_tables()

  @impl Projection
  def handle_event(:enrollment_created, %IntegrationEvent{} = event), do: project_enrollment_created(event)

  def handle_event(:enrollment_cancelled, %IntegrationEvent{} = event), do: project_enrollment_cancelled(event)

  def handle_event(:child_created, %IntegrationEvent{} = event), do: project_child_name_change(event)

  def handle_event(:child_updated, %IntegrationEvent{} = event), do: project_child_name_change(event)

  def handle_event(:conversation_created, %IntegrationEvent{} = event), do: project_conversation_created(event)

  # Private — Bootstrap ───────────────────────────────────────────────────────

  # Trigger: bootstrap phase — read table may be empty or stale
  # Why: cold start recovery — populate read table from authoritative write tables
  # Outcome: messaging_enrolled_children contains one row per (parent_user, program, child)
  defp bootstrap_from_write_tables do
    entries =
      from(e in "enrollments",
        join: c in "children",
        on: c.id == e.child_id,
        join: pp in "parents",
        on: pp.id == e.parent_id,
        where: e.status in ["pending", "confirmed"],
        select: %{
          parent_user_id: type(pp.identity_id, :binary_id),
          program_id: type(e.program_id, :binary_id),
          child_id: type(e.child_id, :binary_id),
          child_first_name: c.first_name
        }
      )
      |> Repo.all()

    if entries == [] do
      0
    else
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      rows =
        Enum.map(entries, fn entry ->
          Map.merge(entry, %{id: Ecto.UUID.generate(), inserted_at: now, updated_at: now})
        end)

      {count, _} =
        Repo.insert_all(EnrolledChildrenSchema, rows,
          on_conflict: {:replace, [:child_first_name, :updated_at]},
          conflict_target: [:parent_user_id, :program_id, :child_id]
        )

      count
    end
  end

  # Private — Event Projections ───────────────────────────────────────────────

  # Trigger: enrollment_created event received
  # Why: a new enrollment needs a lookup row so child names can be resolved
  # Outcome: one row upserted, then re-derivation emits enrolled_children_changed
  defp project_enrollment_created(event) do
    payload = event.payload
    parent_user_id = payload.parent_user_id
    program_id = payload.program_id
    child_id = payload.child_id
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Trigger: event payload lacks child_first_name
    # Why: Enrollment context doesn't know the name; without this, rows stay nil
    #      until a child_updated event fires — which never happens for enrollments
    #      of pre-existing, unedited children
    # Outcome: name resolved from children table (nil only if child concurrently deleted)
    child_first_name = resolve_child_first_name(child_id)

    %EnrolledChildrenSchema{}
    |> Ecto.Changeset.change(%{
      id: Ecto.UUID.generate(),
      parent_user_id: parent_user_id,
      program_id: program_id,
      child_id: child_id,
      child_first_name: child_first_name,
      inserted_at: now,
      updated_at: now
    })
    |> Repo.insert!(
      on_conflict: {:replace, [:child_first_name, :updated_at]},
      conflict_target: [:parent_user_id, :program_id, :child_id]
    )

    re_derive_and_emit(parent_user_id, program_id)
  end

  # Trigger: project_enrollment_created needs child's first_name
  # Why: the enrollment_created event payload does not carry the name
  # Outcome: children.first_name for the given child_id, or nil if the row is missing
  defp resolve_child_first_name(child_id) do
    name =
      Repo.one(
        from(c in "children",
          where: c.id == type(^child_id, :binary_id),
          select: c.first_name
        )
      )

    if is_nil(name) do
      Logger.warning("EnrolledChildren: child row not found when resolving first_name",
        child_id: child_id
      )
    end

    name
  end

  # Trigger: enrollment_cancelled event received
  # Why: cancelled enrollments should not appear in child name lists
  # Outcome: row deleted, then re-derivation emits enrolled_children_changed
  #
  # Special: the event doesn't carry parent_user_id, so we look it up from
  # the existing row before deleting it
  defp project_enrollment_cancelled(event) do
    payload = event.payload
    child_id = payload.child_id
    program_id = payload.program_id

    parent_user_id =
      from(e in EnrolledChildrenSchema,
        where: e.child_id == ^child_id and e.program_id == ^program_id,
        select: e.parent_user_id,
        limit: 1
      )
      |> Repo.one()

    if parent_user_id do
      from(e in EnrolledChildrenSchema,
        where: e.child_id == ^child_id and e.program_id == ^program_id
      )
      |> Repo.delete_all()

      re_derive_and_emit(parent_user_id, program_id)
    end
  end

  # Trigger: child_created or child_updated event received
  # Why: child's first_name may have changed, update all matching lookup rows
  # Outcome: child_first_name updated, then re-derivation for each affected (parent, program)
  defp project_child_name_change(event) do
    payload = event.payload
    child_id = payload.child_id
    first_name = payload.first_name
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    affected =
      from(e in EnrolledChildrenSchema,
        where: e.child_id == ^child_id,
        select: {e.parent_user_id, e.program_id}
      )
      |> Repo.all()

    if affected != [] do
      from(e in EnrolledChildrenSchema, where: e.child_id == ^child_id)
      |> Repo.update_all(set: [child_first_name: first_name, updated_at: now])

      affected
      |> Enum.uniq()
      |> Enum.each(fn {parent_user_id, program_id} ->
        re_derive_and_emit(parent_user_id, program_id)
      end)
    end
  end

  # Trigger: conversation_created event received
  # Why: new conversations need child names resolved for their participants
  # Outcome: enrolled_children_changed emitted for each participant with enrolled children
  #
  # Special: uses event payload directly for conversation_id and participant_ids
  # because the ConversationSummaries row may not exist yet
  defp project_conversation_created(event) do
    payload = event.payload
    program_id = Map.get(payload, :program_id)
    conversation_type = payload |> Map.get(:type, "direct") |> to_string()

    if conversation_type == "direct" and program_id do
      emit_enrolled_children_for_direct_participants(
        payload.conversation_id,
        Map.get(payload, :participant_ids, []),
        program_id
      )
    end
  end

  defp emit_enrolled_children_for_direct_participants(conversation_id, participant_ids, program_id) do
    Enum.each(participant_ids, fn user_id ->
      child_names = get_child_names(user_id, program_id)

      if child_names != [] do
        emit_enrolled_children_changed(conversation_id, child_names)
      end
    end)
  end

  # Private — Re-derivation ───────────────────────────────────────────────────

  # Trigger: a row in messaging_enrolled_children was added, removed, or updated
  # Why: downstream consumers (ConversationSummaries) need the updated child name list
  # Outcome: enrolled_children_changed domain event emitted for each affected conversation
  defp re_derive_and_emit(parent_user_id, program_id) do
    conversation_ids =
      from(s in ConversationSummarySchema,
        where:
          s.user_id == ^parent_user_id and
            s.program_id == ^program_id and
            s.conversation_type == "direct",
        select: s.conversation_id,
        distinct: true
      )
      |> Repo.all()

    if conversation_ids != [] do
      child_names = get_child_names(parent_user_id, program_id)

      Enum.each(conversation_ids, fn conversation_id ->
        emit_enrolled_children_changed(conversation_id, child_names)
      end)
    end
  end

  # Trigger: need sorted child names for a (parent_user, program) pair
  # Why: child names are displayed alphabetically, nil names excluded
  # Outcome: list of non-nil first names, sorted alphabetically
  defp get_child_names(parent_user_id, program_id) do
    from(e in EnrolledChildrenSchema,
      where:
        e.parent_user_id == ^parent_user_id and
          e.program_id == ^program_id and
          not is_nil(e.child_first_name),
      select: e.child_first_name,
      order_by: e.child_first_name
    )
    |> Repo.all()
  end

  # Trigger: child names resolved for a conversation
  # Why: ConversationSummaries projection listens for this event to update its read table
  # Outcome: domain event broadcast on PubSub
  defp emit_enrolled_children_changed(conversation_id, child_names) do
    event =
      DomainEvent.new(
        :enrolled_children_changed,
        conversation_id,
        :conversation,
        %{
          conversation_id: conversation_id,
          enrolled_child_names: child_names
        }
      )

    Phoenix.PubSub.broadcast(
      KlassHero.PubSub,
      @enrolled_children_changed_topic,
      {:domain_event, event}
    )
  end
end
