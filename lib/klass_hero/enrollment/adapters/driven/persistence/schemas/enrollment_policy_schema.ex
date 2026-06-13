defmodule KlassHero.Enrollment.Adapters.Driven.Persistence.Schemas.EnrollmentPolicySchema do
  @moduledoc """
  Ecto schema for the `enrollment_policies` table.
  Use `EnrollmentPolicyMapper` to convert to/from domain `EnrollmentPolicy`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "enrollment_policies" do
    field :program_id, :binary_id
    field :min_enrollment, :integer
    field :max_enrollment, :integer

    timestamps()
  end

  @required_fields ~w(program_id)a
  @optional_fields ~w(min_enrollment max_enrollment)a

  @doc """
  Changeset for enrollment policy creation or update.
  Both `min_enrollment` and `max_enrollment` are optional positive integers;
  DB constraints enforce bounds and uniqueness per program.
  """
  def changeset(schema \\ %__MODULE__{}, attrs) do
    schema
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:min_enrollment, greater_than_or_equal_to: 1)
    |> validate_number(:max_enrollment, greater_than_or_equal_to: 1)
    |> validate_min_not_exceeds_max()
    |> unique_constraint(:program_id)
    |> check_constraint(:min_enrollment, name: :min_enrollment_positive)
    |> check_constraint(:max_enrollment, name: :max_enrollment_positive)
    |> check_constraint(:min_enrollment, name: :min_not_exceeds_max)
  end

  defp validate_min_not_exceeds_max(changeset) do
    min = get_field(changeset, :min_enrollment)
    max = get_field(changeset, :max_enrollment)

    if is_integer(min) and is_integer(max) and min > max do
      add_error(changeset, :min_enrollment, "must not exceed maximum enrollment")
    else
      changeset
    end
  end
end
