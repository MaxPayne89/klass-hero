defmodule KlassHero.Enrollment.Enrollment do
  @moduledoc """
  An enrollment in a program (`enrollments` table) — the aggregate root of the
  Enrollment context.

  This module is both the Ecto schema and the struct consumers pattern-match.
  The changesets are the validation gatekeepers; the lifecycle transitions
  (`confirm/1`, `complete/1`, `cancel/2`) and predicates are the functional core.

  ## Status Lifecycle

      :pending → :confirmed → :completed
          ↓           ↓
      :cancelled  :cancelled
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.ProgramCatalog.Program

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  @valid_statuses [:pending, :confirmed, :completed, :cancelled]
  @valid_payment_methods ~w(card transfer)

  schema "enrollments" do
    belongs_to :program, Program
    field :child_id, :binary_id
    field :parent_id, :binary_id

    field :status, Ecto.Enum, values: [:pending, :confirmed, :completed, :cancelled]
    field :enrolled_at, :utc_datetime
    field :confirmed_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :cancelled_at, :utc_datetime
    field :cancellation_reason, :string
    field :subtotal, :decimal
    field :vat_amount, :decimal
    field :card_fee_amount, :decimal
    field :total_amount, :decimal
    field :payment_method, :string
    field :special_requirements, :string

    timestamps()
  end

  @type t :: %__MODULE__{}

  @required_fields ~w(program_id parent_id status enrolled_at)a
  @optional_fields ~w(
    child_id
    confirmed_at completed_at cancelled_at cancellation_reason
    subtotal vat_amount card_fee_amount total_amount
    payment_method special_requirements
  )a

  @doc """
  Changeset for new enrollment creation.

  `child_id` is required here but nullable in the DB — it is nullified via `ON DELETE SET NULL`
  when a child is deleted, never via application code.
  """
  def create_changeset(enrollment \\ %__MODULE__{}, attrs) do
    enrollment
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields ++ [:child_id])
    |> validate_inclusion(:payment_method, @valid_payment_methods ++ [nil])
    |> validate_length(:cancellation_reason, max: 1000)
    |> validate_length(:special_requirements, max: 500)
    |> validate_number(:subtotal, greater_than_or_equal_to: 0)
    |> validate_number(:vat_amount, greater_than_or_equal_to: 0)
    |> validate_number(:card_fee_amount, greater_than_or_equal_to: 0)
    |> validate_number(:total_amount, greater_than_or_equal_to: 0)
    |> unique_constraint([:program_id, :child_id],
      name: :enrollments_program_child_active_index,
      message: "Active enrollment already exists for this child and program"
    )
    |> foreign_key_constraint(:program_id)
    |> foreign_key_constraint(:child_id)
    |> foreign_key_constraint(:parent_id)
  end

  @doc """
  Changeset for updating an existing enrollment. `program_id`, `child_id`, and `parent_id` are immutable.
  """
  def update_changeset(enrollment, attrs) do
    # child_id is excluded here — it is only nullified at the DB level via ON DELETE SET NULL.
    updatable_fields = Enum.reject(@optional_fields, &(&1 == :child_id))

    enrollment
    |> cast(attrs, updatable_fields ++ [:status])
    |> validate_inclusion(:payment_method, @valid_payment_methods ++ [nil])
    |> validate_length(:cancellation_reason, max: 1000)
    |> validate_length(:special_requirements, max: 500)
    |> validate_number(:subtotal, greater_than_or_equal_to: 0)
    |> validate_number(:vat_amount, greater_than_or_equal_to: 0)
    |> validate_number(:card_fee_amount, greater_than_or_equal_to: 0)
    |> validate_number(:total_amount, greater_than_or_equal_to: 0)
  end

  @doc """
  No-op changeset required by Backpex when edit is disabled via `can?/3`.
  """
  def admin_changeset(schema, _attrs, _metadata), do: change(schema)

  @doc """
  Confirms a pending enrollment.

  Returns `{:ok, enrollment}` with status `:confirmed` and `confirmed_at` set,
  or `{:error, :invalid_status_transition}` if not pending.
  """
  @spec confirm(t()) :: {:ok, t()} | {:error, :invalid_status_transition}
  def confirm(%__MODULE__{status: :pending} = enrollment) do
    {:ok, %{enrollment | status: :confirmed, confirmed_at: DateTime.utc_now()}}
  end

  def confirm(%__MODULE__{}), do: {:error, :invalid_status_transition}

  @doc """
  Completes a confirmed enrollment.

  Returns `{:ok, enrollment}` with status `:completed` and `completed_at` set,
  or `{:error, :invalid_status_transition}` if not confirmed.
  """
  @spec complete(t()) :: {:ok, t()} | {:error, :invalid_status_transition}
  def complete(%__MODULE__{status: :confirmed} = enrollment) do
    {:ok, %{enrollment | status: :completed, completed_at: DateTime.utc_now()}}
  end

  def complete(%__MODULE__{}), do: {:error, :invalid_status_transition}

  @doc """
  Cancels a pending or confirmed enrollment.

  Returns `{:ok, enrollment}` with status `:cancelled`, or
  `{:error, :invalid_status_transition}` if already completed or cancelled.
  """
  @spec cancel(t(), String.t() | nil) :: {:ok, t()} | {:error, :invalid_status_transition}
  def cancel(enrollment, reason \\ nil)

  def cancel(%__MODULE__{status: status} = enrollment, reason) when status in [:pending, :confirmed] do
    {:ok, %{enrollment | status: :cancelled, cancelled_at: DateTime.utc_now(), cancellation_reason: reason}}
  end

  def cancel(%__MODULE__{}, _reason), do: {:error, :invalid_status_transition}

  @doc """
  Tuple-returning input guard for a cancellation reason.

  Returns `{:ok, reason}` when the reason is a non-empty binary,
  `{:error, :invalid_reason}` otherwise. Designed to run at the use-case
  boundary in a `with` chain — fails fast before any DB lookup.
  """
  @spec ensure_reason_present(String.t() | nil) :: {:ok, String.t()} | {:error, :invalid_reason}
  def ensure_reason_present(reason) when is_binary(reason) and byte_size(reason) > 0, do: {:ok, reason}
  def ensure_reason_present(_reason), do: {:error, :invalid_reason}

  @doc "Returns true if enrollment status is :pending"
  @spec pending?(t()) :: boolean()
  def pending?(%__MODULE__{status: :pending}), do: true
  def pending?(%__MODULE__{}), do: false

  @doc "Returns true if enrollment status is :confirmed"
  @spec confirmed?(t()) :: boolean()
  def confirmed?(%__MODULE__{status: :confirmed}), do: true
  def confirmed?(%__MODULE__{}), do: false

  @doc "Returns true if enrollment status is :completed"
  @spec completed?(t()) :: boolean()
  def completed?(%__MODULE__{status: :completed}), do: true
  def completed?(%__MODULE__{}), do: false

  @doc "Returns true if enrollment status is :cancelled"
  @spec cancelled?(t()) :: boolean()
  def cancelled?(%__MODULE__{status: :cancelled}), do: true
  def cancelled?(%__MODULE__{}), do: false

  @doc "Returns true if enrollment is active (pending or confirmed)"
  @spec active?(t()) :: boolean()
  def active?(%__MODULE__{status: status}) when status in [:pending, :confirmed], do: true
  def active?(%__MODULE__{}), do: false

  @doc "Returns all valid enrollment statuses"
  @spec valid_statuses() :: [atom()]
  def valid_statuses, do: @valid_statuses

  @doc "Returns all valid payment methods"
  @spec valid_payment_methods() :: [String.t()]
  def valid_payment_methods, do: @valid_payment_methods
end
