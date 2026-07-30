defmodule KlassHero.Enrollment.Notifications do
  @moduledoc """
  Tells mounted LiveViews that a piece of enrollment state changed.

  Replaces the `NotifyLiveViews` bus handler. A LiveView receives a tagged tuple
  naming what changed and the id it needs to refetch, never a `%DomainEvent{}`.

      {:enrollment_confirmed, enrollment_id}   # provider-scoped topic
      {:participant_policy_set, program_id}    # one shared topic

  The asymmetry is deliberate. Confirmations are scoped per provider because only
  that provider's dashboard cares, so the topic does the filtering. Participant
  policies go to one topic every open program page listens on, so the *message*
  carries the program id and each page filters itself.

  Best-effort, always `:ok` — the write has already committed, and a dropped
  refresh costs a stale view until the next render (ADR-0014).
  """

  @doc """
  The provider-scoped Enrollment topic. Publisher (here) and subscribers
  (`Provider.OverviewLive`) both call this, so the string cannot drift.
  """
  @spec provider_scoped_topic(atom(), String.t()) :: String.t()
  def provider_scoped_topic(event_type, provider_id) when is_atom(event_type) and is_binary(provider_id) do
    "enrollment:#{event_type}:provider:#{provider_id}"
  end

  @doc "The shared topic every mounted program page listens on for policy changes."
  @spec participant_policy_topic() :: String.t()
  def participant_policy_topic, do: "enrollment:participant_policy_set"

  @spec enrollment_confirmed(String.t(), String.t()) :: :ok
  def enrollment_confirmed(enrollment_id, provider_id) do
    :enrollment_confirmed
    |> provider_scoped_topic(provider_id)
    |> broadcast({:enrollment_confirmed, enrollment_id})
  end

  @spec participant_policy_set(String.t()) :: :ok
  def participant_policy_set(program_id) do
    broadcast(participant_policy_topic(), {:participant_policy_set, program_id})
  end

  defp broadcast(topic, message) do
    Phoenix.PubSub.broadcast(KlassHero.PubSub, topic, message)
    :ok
  end
end
