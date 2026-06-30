defmodule KlassHero.Participation.ProgramSession do
  @moduledoc """
  A scheduled program session: the Ecto schema and the struct other code
  pattern-matches on, plus the status state machine.

  ## Status Lifecycle

  ```
  :scheduled → :in_progress → :completed
       ↓
  :cancelled
  ```
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.Participation.ParticipationRecord

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "program_sessions" do
    field :program_id, :binary_id
    field :session_date, :date
    field :start_time, :time
    field :end_time, :time
    field :status, Ecto.Enum, values: [:scheduled, :in_progress, :completed, :cancelled]
    field :location, :string
    field :notes, :string
    field :max_capacity, :integer
    field :lock_version, :integer, default: 1

    has_many :participation_records, ParticipationRecord, foreign_key: :session_id

    timestamps(type: :utc_datetime)
  end

  @type status :: :scheduled | :in_progress | :completed | :cancelled
  @type t :: %__MODULE__{}

  @valid_statuses [:scheduled, :in_progress, :completed, :cancelled]

  @required_fields [:program_id, :session_date, :start_time, :end_time, :status]
  @optional_fields [:location, :notes, :max_capacity, :lock_version]

  @doc "Creates a changeset for inserting a new session."
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_number(:max_capacity, greater_than: 0)
    |> validate_time_range()
    |> unique_constraint([:program_id, :session_date, :start_time],
      name: :program_sessions_program_id_session_date_start_time_index,
      message: "session already exists at this time"
    )
    |> optimistic_lock(:lock_version)
  end

  @doc "Creates a changeset for updating an existing session."
  def update_changeset(session, attrs) do
    session
    |> cast(attrs, @optional_fields ++ [:status])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_number(:max_capacity, greater_than: 0)
    |> optimistic_lock(:lock_version)
  end

  defp validate_time_range(changeset) do
    start_time = get_field(changeset, :start_time)
    end_time = get_field(changeset, :end_time)

    if start_time && end_time && Time.compare(start_time, end_time) != :lt do
      add_error(changeset, :end_time, "must be after start time")
    else
      changeset
    end
  end

  @doc "Builds a scheduled session struct, validating the time range."
  @spec new(map()) :: {:ok, t()} | {:error, :missing_required_fields | :invalid_time_range}
  def new(attrs) when is_map(attrs) do
    with {:ok, id} <- Map.fetch(attrs, :id),
         {:ok, program_id} <- Map.fetch(attrs, :program_id),
         {:ok, session_date} <- Map.fetch(attrs, :session_date),
         {:ok, start_time} <- Map.fetch(attrs, :start_time),
         {:ok, end_time} <- Map.fetch(attrs, :end_time),
         :ok <- validate_time_range(start_time, end_time) do
      {:ok,
       %__MODULE__{
         id: id,
         program_id: program_id,
         session_date: session_date,
         start_time: start_time,
         end_time: end_time,
         status: :scheduled,
         location: Map.get(attrs, :location),
         notes: Map.get(attrs, :notes),
         max_capacity: Map.get(attrs, :max_capacity),
         lock_version: 1
       }}
    else
      :error -> {:error, :missing_required_fields}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_time_range(start_time, end_time) do
    case Time.compare(start_time, end_time) do
      :lt -> :ok
      _ -> {:error, :invalid_time_range}
    end
  end

  @doc "Starts the session. Errors unless `:scheduled`."
  @spec start(t()) :: {:ok, t()} | {:error, :invalid_status_transition}
  def start(%__MODULE__{status: :scheduled} = session), do: {:ok, %{session | status: :in_progress}}
  def start(%__MODULE__{}), do: {:error, :invalid_status_transition}

  @doc "Completes the session. Errors unless `:in_progress`."
  @spec complete(t()) :: {:ok, t()} | {:error, :invalid_status_transition}
  def complete(%__MODULE__{status: :in_progress} = session), do: {:ok, %{session | status: :completed}}
  def complete(%__MODULE__{}), do: {:error, :invalid_status_transition}

  @doc "Cancels the session. Errors unless `:scheduled`."
  @spec cancel(t()) :: {:ok, t()} | {:error, :invalid_status_transition}
  def cancel(%__MODULE__{status: :scheduled} = session), do: {:ok, %{session | status: :cancelled}}
  def cancel(%__MODULE__{}), do: {:error, :invalid_status_transition}

  @doc "Returns true if the session can accept new participants."
  @spec can_accept_participants?(t()) :: boolean()
  def can_accept_participants?(%__MODULE__{status: status}) when status in [:scheduled, :in_progress], do: true
  def can_accept_participants?(%__MODULE__{}), do: false

  @doc "Returns true if the session is currently active."
  @spec in_progress?(t()) :: boolean()
  def in_progress?(%__MODULE__{status: :in_progress}), do: true
  def in_progress?(%__MODULE__{}), do: false

  @doc "Returns the duration of the session in minutes."
  @spec duration_minutes(t()) :: non_neg_integer()
  def duration_minutes(%__MODULE__{start_time: start_time, end_time: end_time}) do
    Time.diff(end_time, start_time, :minute)
  end

  @doc "Returns the list of valid status atoms."
  @spec valid_statuses() :: [status()]
  def valid_statuses, do: @valid_statuses
end
