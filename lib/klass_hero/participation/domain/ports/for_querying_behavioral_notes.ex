defmodule KlassHero.Participation.Domain.Ports.ForQueryingBehavioralNotes do
  @moduledoc """
  Read-only port for querying behavioral notes in the Participation bounded context.

  Defines the contract for behavioral note read operations (CQRS query side).
  Write operations remain in `ForManagingBehavioralNotes`.
  """

  alias KlassHero.Participation.BehavioralNote

  @doc "Retrieves behavioral note by ID. Returns `{:error, :not_found}` if not found."
  @callback get_by_id(binary()) :: {:ok, BehavioralNote.t()} | {:error, :not_found}

  @doc "Lists pending behavioral notes for a parent, ordered by submitted_at desc."
  @callback list_pending_by_parent(binary()) :: [BehavioralNote.t()]

  @doc "Lists approved behavioral notes for a child, ordered by submitted_at desc."
  @callback list_approved_by_child(binary()) :: [BehavioralNote.t()]

  @doc "Batch-lists approved behavioral notes for multiple children, grouped by child_id."
  @callback list_approved_by_children([binary()]) :: %{binary() => [BehavioralNote.t()]}

  @doc "Gets note by participation record and provider. Returns `{:error, :not_found}` if not found."
  @callback get_by_participation_record_and_provider(binary(), binary()) ::
              {:ok, BehavioralNote.t()} | {:error, :not_found}

  @doc "Lists notes for multiple participation records by a single provider."
  @callback list_by_records_and_provider([binary()], binary()) :: [BehavioralNote.t()]

  @doc "Gets note by ID scoped to parent. Returns `{:error, :not_found}` if note doesn't belong to parent."
  @callback get_by_id_and_parent(binary(), binary()) ::
              {:ok, BehavioralNote.t()} | {:error, :not_found}

  @doc "Gets note by ID scoped to provider. Returns `{:error, :not_found}` if note doesn't belong to provider."
  @callback get_by_id_and_provider(binary(), binary()) ::
              {:ok, BehavioralNote.t()} | {:error, :not_found}
end
