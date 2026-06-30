defmodule KlassHero.Participation.Domain.Ports.ForManagingBehavioralNotes do
  @moduledoc """
  Write-only port for behavioral note persistence.

  Defines the contract for behavioral note write operations (CQRS command side).
  Read operations have been moved to `ForQueryingBehavioralNotes`.
  """

  alias KlassHero.Participation.BehavioralNote

  @doc "Creates behavioral note. Returns `{:error, :duplicate_note}` on unique violation."
  @callback create(BehavioralNote.t()) ::
              {:ok, BehavioralNote.t()} | {:error, :duplicate_note | :validation_failed}

  @doc "Updates existing behavioral note. Returns `{:error, :not_found}` if not found."
  @callback update(BehavioralNote.t()) ::
              {:ok, BehavioralNote.t()} | {:error, :not_found | :validation_failed}

  @doc """
  Anonymizes all behavioral notes for a child (GDPR account deletion).

  Receives the anonymized attribute values from the domain model and applies
  them mechanically. The adapter does not decide what "anonymized" means.

  Returns `{:ok, count}`.
  """
  @callback anonymize_all_for_child(binary(), map()) :: {:ok, non_neg_integer()}
end
