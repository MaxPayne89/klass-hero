defmodule KlassHero.Participation.Notifications do
  @moduledoc """
  Tells mounted LiveViews that a piece of participation state changed.

  Replaces the `NotifyLiveViews` bus handler. The difference that matters is the
  wire format: a LiveView receives a tagged tuple naming what changed and the ids
  it needs to refetch, never a `%Event{}`. Nothing in the web layer knows
  the event system exists.

      {:session_changed, session_id}
      {:sessions_generated, program_id}
      {:attendance_changed, %{record_id:, session_id:, child_id:, kind:}}
      :session_notes_changed

  Nine session-lifecycle events collapse to one `:session_changed` because every
  subscriber does the same thing with all of them — refetch that session. The
  distinctions the events draw (started vs completed vs cancelled) are real to the
  domain and invisible to the view.

  ## Topics

  - `participation:provider:{id}` — a provider's whole participation stream
  - `participation:child:{id}` — one child's attendance and notes (#1121)

  Session and attendance events carry `program_id`, so the provider is resolved
  through the ACL. Session-note events carry `provider_id` directly and skip the
  lookup — which is also why they no longer need the generic
  `participation:<aggregate>:<event>` topics they used to be broadcast on.

  ## Failure

  Best-effort, always `:ok`. The write has already committed; a dropped refresh
  costs a stale view until the next render, which is the one loss this system is
  allowed to take (ADR-0014).
  """

  alias KlassHero.Participation.Adapters.Driven.ACL.ProgramProviderResolver
  alias KlassHero.Shared.Domain.Events.Event

  require Logger

  # A session event missing from this list is not a smaller broadcast — it is no
  # broadcast at all: `message/1` falls through to the catch-all `nil` and `notify/1`
  # returns `:ok` having told nobody. The write lands, the projection lands, and
  # every already-mounted LiveView keeps rendering the old row (#1074).
  @session_events [
    :session_created,
    :session_updated,
    :session_started,
    :session_completed,
    :session_cancelled,
    :roster_seeded
  ]

  @attendance_kinds %{
    child_checked_in: :checked_in,
    child_checked_out: :checked_out,
    child_marked_absent: :marked_absent,
    attendance_corrected: :corrected
  }

  @note_events [:session_note_submitted, :session_note_approved, :session_note_rejected]

  @doc "Notifies for each event in turn, preserving the order they were staged in."
  @spec notify_all([Event.t()]) :: :ok
  def notify_all(events), do: Enum.each(events, &notify/1)

  @doc "Notifies every topic that carries this event's UI message."
  @spec notify(Event.t()) :: :ok
  def notify(%Event{} = event) do
    case message(event) do
      nil -> :ok
      message -> Enum.each(topics(event), &broadcast(&1, message))
    end
  end

  @doc """
  The provider-scoped participation topic — one topic carrying all of a provider's
  participation traffic. Provider and staff LiveViews subscribe to it; this module
  publishes to it. One builder, so the two sides cannot drift.
  """
  @spec provider_topic(String.t()) :: String.t()
  def provider_topic(provider_id), do: "participation:provider:#{provider_id}"

  @doc "The child-scoped participation topic, subscribed to per child by parent LiveViews (#1121)."
  @spec child_topic(String.t()) :: String.t()
  def child_topic(child_id), do: "participation:child:#{child_id}"

  # Matching the id out of the payload rather than fetching it: an event missing
  # the id its message is built from falls through to the catch-all and notifies
  # nobody, instead of broadcasting a tuple with a nil in it.
  defp message(%Event{event_type: type, payload: %{session_id: session_id}}) when type in @session_events,
    do: {:session_changed, session_id}

  defp message(%Event{event_type: :sessions_generated, payload: %{program_id: program_id}}),
    do: {:sessions_generated, program_id}

  defp message(%Event{event_type: type, payload: payload}) when is_map_key(@attendance_kinds, type) do
    {:attendance_changed,
     %{
       record_id: Map.get(payload, :record_id),
       session_id: Map.get(payload, :session_id),
       child_id: Map.get(payload, :child_id),
       kind: Map.fetch!(@attendance_kinds, type)
     }}
  end

  defp message(%Event{event_type: type}) when type in @note_events, do: :session_notes_changed

  defp message(%Event{}), do: nil

  defp topics(%Event{payload: payload} = event) do
    provider_topics(event) ++ child_topics(payload)
  end

  # Session notes know their provider; everything else has to ask the catalog.
  defp provider_topics(%Event{event_type: type, payload: payload}) when type in @note_events do
    case Map.fetch(payload, :provider_id) do
      {:ok, provider_id} -> [provider_topic(provider_id)]
      :error -> []
    end
  end

  defp provider_topics(%Event{payload: payload} = event) do
    case Map.fetch(payload, :program_id) do
      {:ok, program_id} -> resolve_provider_topics(program_id, event)
      :error -> []
    end
  end

  defp resolve_provider_topics(program_id, event) do
    case ProgramProviderResolver.resolve_provider_id(program_id) do
      {:ok, provider_id} ->
        [provider_topic(provider_id)]

      {:error, reason} ->
        # Best-effort: the child topic still gets its message. Debug rather than
        # warning because sustained failures belong in metrics, not the log.
        Logger.debug("[Participation.Notifications] Could not resolve provider for program",
          program_id: program_id,
          event_type: event.event_type,
          reason: reason
        )

        []
    end
  end

  defp child_topics(payload) do
    case Map.fetch(payload, :child_id) do
      {:ok, child_id} -> [child_topic(child_id)]
      :error -> []
    end
  end

  defp broadcast(topic, message), do: Phoenix.PubSub.broadcast(KlassHero.PubSub, topic, message)
end
