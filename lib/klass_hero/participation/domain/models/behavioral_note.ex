defmodule KlassHero.Participation.Domain.Models.BehavioralNote do
  @moduledoc """
  Pure domain entity representing a behavioral note about a child's participation.

  ## Design Principles

  This is a pure Elixir struct with no Ecto dependencies, following DDD principles:

  - **Persistence Ignorance**: No knowledge of database schemas or Ecto
  - **Framework Independence**: Pure Elixir struct usable in any context
  - **Encapsulated Business Logic**: All validation and state transitions are domain methods

  ## Status Lifecycle

  ```
  :pending_approval → :approved (final)
  :pending_approval → :rejected → (revise) → :pending_approval
  ```

  Providers submit notes on checked-in/checked-out records. Parents approve or reject.
  Rejected notes can be revised and resubmitted.
  """

  use KlassHero.Shared.Domain.Models.PersistenceSupport

  @enforce_keys [:id, :participation_record_id, :child_id, :provider_id, :content, :status]
  defstruct [
    :id,
    :participation_record_id,
    :child_id,
    :parent_id,
    :provider_id,
    :content,
    :status,
    :rejection_reason,
    :submitted_at,
    :reviewed_at,
    :inserted_at,
    :updated_at
  ]

  @type status :: :pending_approval | :approved | :rejected

  @type t :: %__MODULE__{
          id: String.t(),
          participation_record_id: String.t(),
          child_id: String.t(),
          parent_id: String.t() | nil,
          provider_id: String.t(),
          content: String.t(),
          status: status(),
          rejection_reason: String.t() | nil,
          submitted_at: DateTime.t() | nil,
          reviewed_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @max_content_length 1000

  @doc "Creates a new behavioral note in `:pending_approval` status. Content must be non-blank and at most #{@max_content_length} chars."
  @spec new(map()) ::
          {:ok, t()} | {:error, :missing_required_fields | :blank_content | :content_too_long}
  def new(attrs) when is_map(attrs) do
    with {:ok, id} <- Map.fetch(attrs, :id),
         {:ok, participation_record_id} <- Map.fetch(attrs, :participation_record_id),
         {:ok, child_id} <- Map.fetch(attrs, :child_id),
         {:ok, provider_id} <- Map.fetch(attrs, :provider_id),
         {:ok, content} <- Map.fetch(attrs, :content),
         :ok <- validate_content(content) do
      note = %__MODULE__{
        id: id,
        participation_record_id: participation_record_id,
        child_id: child_id,
        parent_id: Map.get(attrs, :parent_id),
        provider_id: provider_id,
        content: String.trim(content),
        status: :pending_approval,
        submitted_at: DateTime.utc_now()
      }

      {:ok, note}
    else
      :error -> {:error, :missing_required_fields}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Approves a pending note. Only valid from :pending_approval status.
  """
  @spec approve(t()) :: {:ok, t()} | {:error, :invalid_status_transition}
  def approve(%__MODULE__{status: :pending_approval} = note) do
    {:ok, %{note | status: :approved, reviewed_at: DateTime.utc_now()}}
  end

  def approve(%__MODULE__{}), do: {:error, :invalid_status_transition}

  @doc """
  Rejects a pending note with an optional reason. Only valid from :pending_approval status.
  """
  @spec reject(t(), String.t() | nil) :: {:ok, t()} | {:error, :invalid_status_transition}
  def reject(note, reason \\ nil)

  def reject(%__MODULE__{status: :pending_approval} = note, reason) do
    {:ok, %{note | status: :rejected, rejection_reason: reason, reviewed_at: DateTime.utc_now()}}
  end

  def reject(%__MODULE__{}, _reason), do: {:error, :invalid_status_transition}

  @doc """
  Revises a rejected note with new content, resubmitting for approval.
  Only valid from :rejected status. Clears rejection_reason and resets submitted_at.
  """
  @spec revise(t(), String.t()) ::
          {:ok, t()} | {:error, :invalid_status_transition | :blank_content | :content_too_long}
  def revise(%__MODULE__{status: :rejected} = note, new_content) when is_binary(new_content) do
    with :ok <- validate_content(new_content) do
      {:ok,
       %{
         note
         | content: String.trim(new_content),
           status: :pending_approval,
           rejection_reason: nil,
           submitted_at: DateTime.utc_now(),
           reviewed_at: nil
       }}
    end
  end

  def revise(%__MODULE__{}, _content), do: {:error, :invalid_status_transition}

  @doc "Returns true if note is pending approval."
  @spec pending?(t()) :: boolean()
  def pending?(%__MODULE__{status: :pending_approval}), do: true
  def pending?(%__MODULE__{}), do: false

  @doc "Returns true if note is approved."
  @spec approved?(t()) :: boolean()
  def approved?(%__MODULE__{status: :approved}), do: true
  def approved?(%__MODULE__{}), do: false

  @doc "Returns true if note is rejected."
  @spec rejected?(t()) :: boolean()
  def rejected?(%__MODULE__{status: :rejected}), do: true
  def rejected?(%__MODULE__{}), do: false

  @doc "Returns anonymized attribute values for GDPR account deletion. Domain model owns this definition."
  def anonymized_attrs do
    %{
      content: "[Removed - account deleted]",
      rejection_reason: nil,
      # :rejected ensures anonymized notes are excluded from visible views and cannot re-enter approval workflows.
      status: :rejected
    }
  end

  defp validate_content(content) when is_binary(content) do
    trimmed = String.trim(content)

    cond do
      trimmed == "" -> {:error, :blank_content}
      String.length(trimmed) > @max_content_length -> {:error, :content_too_long}
      true -> :ok
    end
  end

  defp validate_content(_), do: {:error, :blank_content}
end
