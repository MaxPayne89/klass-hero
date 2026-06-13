defmodule KlassHero.Enrollment.Adapters.Driven.Persistence.Schemas.EnrollmentSchema do
  @moduledoc """
  Ecto schema for the `enrollments` table.
  Use `EnrollmentMapper` to convert to/from domain `Enrollment`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.Family.Adapters.Driven.Persistence.Schemas.ChildSchema
  alias KlassHero.Family.Adapters.Driven.Persistence.Schemas.ParentProfileSchema
  alias KlassHero.ProgramCatalog.Adapters.Driven.Persistence.Schemas.ProgramSchema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  @valid_payment_methods ~w(card transfer)

  schema "enrollments" do
    belongs_to :program,
               ProgramSchema

    belongs_to :child, ChildSchema

    belongs_to :parent, ParentProfileSchema

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
  def create_changeset(enrollment_schema \\ %__MODULE__{}, attrs) do
    enrollment_schema
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
  def update_changeset(enrollment_schema, attrs) do
    # child_id is excluded here — it is only nullified at the DB level via ON DELETE SET NULL.
    updatable_fields = Enum.reject(@optional_fields, &(&1 == :child_id))

    enrollment_schema
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
end
