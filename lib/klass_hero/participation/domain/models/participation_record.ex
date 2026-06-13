defmodule KlassHero.Participation.Domain.Models.ParticipationRecord do
  @moduledoc """
  Pure domain entity representing a child's participation in a program session.

  ## Design Principles

  This is a pure Elixir struct with no Ecto dependencies, following DDD principles:

  - **Persistence Ignorance**: No knowledge of database schemas or Ecto
  - **Framework Independence**: Pure Elixir struct usable in any context
  - **Encapsulated Business Logic**: All validation and state transitions are domain methods

  ## Status Lifecycle

  ```
  :registered → :checked_in → :checked_out
                    ↓
               :absent (if session completed without check-in)
  ```

  ## Timestamps

  All timestamp fields (`check_in_at`, `check_out_at`, `inserted_at`, `updated_at`)
  are `DateTime.t()` in UTC timezone.
  """

  use KlassHero.Shared.Domain.Models.PersistenceSupport

  @enforce_keys [:id, :session_id, :child_id, :status]
  defstruct [
    :id,
    :session_id,
    :child_id,
    :parent_id,
    :provider_id,
    :status,
    :check_in_at,
    :check_in_notes,
    :check_in_by,
    :check_out_at,
    :check_out_notes,
    :check_out_by,
    :inserted_at,
    :updated_at,
    lock_version: 1
  ]

  @type status :: :registered | :checked_in | :checked_out | :absent

  @type t :: %__MODULE__{
          id: String.t(),
          session_id: String.t(),
          child_id: String.t(),
          parent_id: String.t() | nil,
          provider_id: String.t() | nil,
          status: status(),
          check_in_at: DateTime.t() | nil,
          check_in_notes: String.t() | nil,
          check_in_by: String.t() | nil,
          check_out_at: DateTime.t() | nil,
          check_out_notes: String.t() | nil,
          check_out_by: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil,
          lock_version: pos_integer()
        }

  @valid_statuses [:registered, :checked_in, :checked_out, :absent]

  @spec new(map()) :: {:ok, t()} | {:error, :missing_required_fields}
  def new(attrs) when is_map(attrs) do
    with {:ok, id} <- Map.fetch(attrs, :id),
         {:ok, session_id} <- Map.fetch(attrs, :session_id),
         {:ok, child_id} <- Map.fetch(attrs, :child_id) do
      record = %__MODULE__{
        id: id,
        session_id: session_id,
        child_id: child_id,
        parent_id: Map.get(attrs, :parent_id),
        provider_id: Map.get(attrs, :provider_id),
        status: :registered,
        lock_version: 1
      }

      {:ok, record}
    else
      :error -> {:error, :missing_required_fields}
    end
  end

  @doc """
  Checks in the child to the session.

  Returns error if not in :registered status.
  """
  @spec check_in(t(), String.t(), String.t() | nil) ::
          {:ok, t()} | {:error, :invalid_status_transition}
  def check_in(record, checked_in_by, notes \\ nil)

  def check_in(%__MODULE__{status: :registered} = record, checked_in_by, notes) do
    updated =
      %{
        record
        | status: :checked_in,
          check_in_at: DateTime.utc_now(),
          check_in_by: checked_in_by,
          check_in_notes: notes
      }

    {:ok, updated}
  end

  def check_in(%__MODULE__{}, _checked_in_by, _notes) do
    {:error, :invalid_status_transition}
  end

  @doc """
  Checks out the child from the session.

  Returns error if not in :checked_in status.
  """
  @spec check_out(t(), String.t(), String.t() | nil) ::
          {:ok, t()} | {:error, :invalid_status_transition}
  def check_out(record, checked_out_by, notes \\ nil)

  def check_out(%__MODULE__{status: :checked_in} = record, checked_out_by, notes) do
    updated =
      %{
        record
        | status: :checked_out,
          check_out_at: DateTime.utc_now(),
          check_out_by: checked_out_by,
          check_out_notes: notes
      }

    {:ok, updated}
  end

  def check_out(%__MODULE__{}, _checked_out_by, _notes) do
    {:error, :invalid_status_transition}
  end

  @doc """
  Marks the child as absent (session completed without check-in).

  Returns error if already checked in or checked out.
  """
  @spec mark_absent(t()) :: {:ok, t()} | {:error, :invalid_status_transition}
  def mark_absent(%__MODULE__{status: :registered} = record) do
    {:ok, %{record | status: :absent}}
  end

  def mark_absent(%__MODULE__{}) do
    {:error, :invalid_status_transition}
  end

  @doc "Returns true if child is currently checked in."
  @spec checked_in?(t()) :: boolean()
  def checked_in?(%__MODULE__{status: :checked_in}), do: true
  def checked_in?(%__MODULE__{}), do: false

  @doc "Returns true if child has completed their session (checked out)."
  @spec completed?(t()) :: boolean()
  def completed?(%__MODULE__{status: :checked_out}), do: true
  def completed?(%__MODULE__{}), do: false

  @doc "Returns true if a behavioral note can be added to this record."
  @spec allows_behavioral_note?(t()) :: boolean()
  def allows_behavioral_note?(%__MODULE__{status: status}), do: status in [:checked_in, :checked_out]

  @doc "Returns list of valid status atoms."
  @spec valid_statuses() :: [status()]
  def valid_statuses, do: @valid_statuses

  @doc """
  Admin correction — allows any status transition and time edits.

  Unlike `check_in/3` and `check_out/3`, this bypasses the forward-only
  state machine for administrative fixes.

  ## Validations
  - At least one field must change (status or times)
  - `check_out_at` requires `check_in_at` to be present (on the record or in attrs)
  - Status must be a valid status atom
  """
  @spec admin_correct(t(), map()) :: {:ok, t()} | {:error, atom()}
  def admin_correct(%__MODULE__{} = record, attrs) when is_map(attrs) do
    with :ok <- validate_has_changes(record, attrs),
         :ok <- validate_status(attrs),
         :ok <- validate_check_out_consistency(record, attrs) do
      corrected = apply_corrections(record, attrs)
      validate_temporal_ordering(corrected)
    end
  end

  defp validate_has_changes(record, attrs) do
    if any_change?(record, attrs), do: :ok, else: {:error, :no_changes}
  end

  defp any_change?(record, attrs) do
    status_changed?(record, attrs) or
      field_changed?(record, attrs, :check_in_at) or
      field_changed?(record, attrs, :check_out_at) or
      field_changed?(record, attrs, :check_in_notes) or
      field_changed?(record, attrs, :check_out_notes)
  end

  defp status_changed?(record, attrs) do
    Map.has_key?(attrs, :status) and attrs.status != record.status
  end

  defp field_changed?(record, attrs, field) do
    Map.has_key?(attrs, field) and Map.get(attrs, field) != Map.get(record, field)
  end

  defp validate_status(%{status: status}) when status not in @valid_statuses, do: {:error, :invalid_status}

  defp validate_status(_attrs), do: :ok

  defp validate_check_out_consistency(record, attrs) do
    new_status = Map.get(attrs, :status, record.status)
    setting_check_out = Map.has_key?(attrs, :check_out_at)
    has_check_in = record.check_in_at != nil or Map.has_key?(attrs, :check_in_at)

    # check_out requires check_in — rejects logically impossible corrections.
    if (new_status == :checked_out or setting_check_out) and not has_check_in do
      {:error, :check_out_requires_check_in}
    else
      :ok
    end
  end

  defp apply_corrections(record, attrs) do
    record
    |> maybe_update(:status, attrs)
    |> maybe_update(:check_in_at, attrs)
    |> maybe_update(:check_out_at, attrs)
    |> clear_downstream_fields(attrs)
    |> maybe_update(:check_in_notes, attrs)
    |> maybe_update(:check_out_notes, attrs)
  end

  defp maybe_update(record, field, attrs) do
    case Map.fetch(attrs, field) do
      {:ok, value} -> Map.put(record, field, value)
      :error -> record
    end
  end

  # Reverting to :checked_in invalidates check-out data.
  defp clear_downstream_fields(record, %{status: :checked_in}) do
    %{record | check_out_at: nil, check_out_by: nil, check_out_notes: nil}
  end

  # :registered and :absent precede any check-in — clear all timing data.
  defp clear_downstream_fields(record, %{status: status}) when status in [:registered, :absent] do
    %{
      record
      | check_in_at: nil,
        check_in_by: nil,
        check_in_notes: nil,
        check_out_at: nil,
        check_out_by: nil,
        check_out_notes: nil
    }
  end

  defp clear_downstream_fields(record, _attrs), do: record

  # Rejects corrections where check_out_at would precede check_in_at.
  defp validate_temporal_ordering(%__MODULE__{check_in_at: %DateTime{} = ci, check_out_at: %DateTime{} = co} = record) do
    case DateTime.compare(ci, co) do
      :gt -> {:error, :check_in_must_precede_check_out}
      _ -> {:ok, record}
    end
  end

  defp validate_temporal_ordering(record), do: {:ok, record}
end
