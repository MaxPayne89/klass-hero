defmodule KlassHero.Participation.ParticipationRecord do
  @moduledoc """
  A child's participation in a program session: the Ecto schema and the struct
  other code pattern-matches on, plus the attendance state machine.

  ## Status Lifecycle

  ```
  :registered ──→ :checked_in ──→ :checked_out
       │               ▲
       ↓               │ arrived late
    :absent ───────────┘
  ```

  A child becomes `:absent` two ways: marked by hand with a reason, or swept
  there when the session is completed with them still `:registered`. The record
  itself cannot tell those apart — who marked it, when, and why live on
  `AttendanceTransition` (#1329).

  `admin_correct/2` bypasses all of this on purpose; it is the only way back
  from `:checked_out`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.Participation.ProgramSession

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "participation_records" do
    field :child_id, :binary_id
    field :parent_id, :binary_id
    field :provider_id, :binary_id
    field :status, Ecto.Enum, values: [:registered, :checked_in, :checked_out, :absent]
    field :check_in_at, :utc_datetime
    field :check_in_notes, :string
    field :check_in_by, :binary_id
    field :check_out_at, :utc_datetime
    field :check_out_notes, :string
    field :check_out_by, :binary_id
    field :lock_version, :integer, default: 1

    belongs_to :session, ProgramSession

    timestamps(type: :utc_datetime)
  end

  @type status :: :registered | :checked_in | :checked_out | :absent
  @type t :: %__MODULE__{}

  @valid_statuses [:registered, :checked_in, :checked_out, :absent]

  @required_fields [:session_id, :child_id, :status]
  @optional_fields [
    :parent_id,
    :provider_id,
    :check_in_at,
    :check_in_notes,
    :check_in_by,
    :check_out_at,
    :check_out_notes,
    :check_out_by,
    :lock_version
  ]

  @doc "Creates a changeset for inserting a new participation record."
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @valid_statuses)
    |> unique_constraint([:session_id, :child_id],
      name: :participation_records_session_id_child_id_index,
      message: "child already registered for this session"
    )
    |> foreign_key_constraint(:session_id)
    |> optimistic_lock(:lock_version)
  end

  @doc "Creates a changeset for updating an existing participation record."
  def update_changeset(record, attrs) do
    record
    |> cast(attrs, @optional_fields ++ [:status])
    |> validate_inclusion(:status, @valid_statuses)
    |> optimistic_lock(:lock_version)
  end

  @doc "Builds a registered participation record struct."
  @spec new(map()) :: {:ok, t()} | {:error, :missing_required_fields}
  def new(attrs) when is_map(attrs) do
    with {:ok, id} <- Map.fetch(attrs, :id),
         {:ok, session_id} <- Map.fetch(attrs, :session_id),
         {:ok, child_id} <- Map.fetch(attrs, :child_id) do
      {:ok,
       %__MODULE__{
         id: id,
         session_id: session_id,
         child_id: child_id,
         parent_id: Map.get(attrs, :parent_id),
         provider_id: Map.get(attrs, :provider_id),
         status: :registered,
         lock_version: 1
       }}
    else
      :error -> {:error, :missing_required_fields}
    end
  end

  @doc """
  Checks in the child. Errors once the child has already arrived.

  Accepted from `:absent` as well as `:registered` (#1329): a child marked absent
  at 09:05 who walks in at 09:20 is checked in from the roster, not corrected by
  an admin. The count a provider sees stays right either way — `:absent` is not
  counted as present, so the check-in still adds one.
  """
  @spec check_in(t(), String.t(), String.t() | nil) ::
          {:ok, t()} | {:error, :invalid_status_transition}
  def check_in(record, checked_in_by, notes \\ nil)

  def check_in(%__MODULE__{status: status} = record, checked_in_by, notes) when status in [:registered, :absent] do
    {:ok,
     %{
       record
       | status: :checked_in,
         check_in_at: DateTime.utc_now(),
         check_in_by: checked_in_by,
         check_in_notes: notes
     }}
  end

  def check_in(%__MODULE__{}, _checked_in_by, _notes), do: {:error, :invalid_status_transition}

  @doc "Checks out the child. Errors unless `:checked_in`."
  @spec check_out(t(), String.t(), String.t() | nil) ::
          {:ok, t()} | {:error, :invalid_status_transition}
  def check_out(record, checked_out_by, notes \\ nil)

  def check_out(%__MODULE__{status: :checked_in} = record, checked_out_by, notes) do
    {:ok,
     %{
       record
       | status: :checked_out,
         check_out_at: DateTime.utc_now(),
         check_out_by: checked_out_by,
         check_out_notes: notes
     }}
  end

  def check_out(%__MODULE__{}, _checked_out_by, _notes), do: {:error, :invalid_status_transition}

  @doc "Marks the child absent. Errors unless `:registered`."
  @spec mark_absent(t()) :: {:ok, t()} | {:error, :invalid_status_transition}
  def mark_absent(%__MODULE__{status: :registered} = record), do: {:ok, %{record | status: :absent}}
  def mark_absent(%__MODULE__{}), do: {:error, :invalid_status_transition}

  @doc """
  Marks the child absent, in the shape the shared attendance path expects.

  The actor and reason are accepted to match `check_in/3` — `run_attendance_action/5`
  calls every verb with `(record, actor_id, notes)` — but are not stored on the
  record. An absence's who and why live on `AttendanceTransition` (#1329).
  """
  @spec mark_absent(t(), String.t(), String.t() | nil) :: {:ok, t()} | {:error, :invalid_status_transition}
  def mark_absent(%__MODULE__{} = record, _absent_by, _reason), do: mark_absent(record)

  @doc "Returns true if the child is currently checked in."
  @spec checked_in?(t()) :: boolean()
  def checked_in?(%__MODULE__{status: :checked_in}), do: true
  def checked_in?(%__MODULE__{}), do: false

  @doc "Returns true if the child has checked out."
  @spec completed?(t()) :: boolean()
  def completed?(%__MODULE__{status: :checked_out}), do: true
  def completed?(%__MODULE__{}), do: false

  @doc "Returns true if a session note can be added to this record."
  @spec allows_session_note?(t()) :: boolean()
  def allows_session_note?(%__MODULE__{status: status}), do: status in [:checked_in, :checked_out]

  @doc "Returns the list of valid status atoms."
  @spec valid_statuses() :: [status()]
  def valid_statuses, do: @valid_statuses

  @doc """
  Admin correction — allows any status transition and time edits, bypassing the
  forward-only state machine.

  ## Validations
  - At least one field must change (status or times)
  - `check_out_at` requires `check_in_at` (on the record or in attrs)
  - Status must be a valid status atom
  - `check_out_at` must not precede `check_in_at`
  """
  @spec admin_correct(t(), map()) :: {:ok, t()} | {:error, atom()}
  def admin_correct(%__MODULE__{} = record, attrs) when is_map(attrs) do
    with :ok <- validate_has_changes(record, attrs),
         :ok <- validate_status(attrs),
         :ok <- validate_check_out_consistency(record, attrs) do
      record
      |> apply_corrections(attrs)
      |> validate_temporal_ordering()
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

  defp clear_downstream_fields(record, %{status: :checked_in}) do
    %{record | check_out_at: nil, check_out_by: nil, check_out_notes: nil}
  end

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

  defp validate_temporal_ordering(%__MODULE__{check_in_at: %DateTime{} = ci, check_out_at: %DateTime{} = co} = record) do
    case DateTime.compare(ci, co) do
      :gt -> {:error, :check_in_must_precede_check_out}
      _ -> {:ok, record}
    end
  end

  defp validate_temporal_ordering(record), do: {:ok, record}
end
