defmodule KlassHero.Enrollment.Adapters.Driven.Persistence.Schemas.ParticipantPolicySchema do
  @moduledoc """
  Ecto schema for the `participant_policies` table.
  Use `ParticipantPolicyMapper` to convert to/from domain `ParticipantPolicy`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.Enrollment.Domain.Models.ParticipantPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "participant_policies" do
    field :program_id, :binary_id
    field :eligibility_at, :string, default: "registration"
    field :min_age_months, :integer
    field :max_age_months, :integer
    field :allowed_genders, {:array, :string}, default: []
    field :min_grade, :integer
    field :max_grade, :integer

    timestamps()
  end

  @required_fields ~w(program_id)a
  @optional_fields ~w(eligibility_at min_age_months max_age_months allowed_genders min_grade max_grade)a

  @doc """
  Changeset for participant policy creation or update.
  All restriction fields are optional; DB constraints enforce range validity and uniqueness per program.
  """
  def changeset(schema \\ %__MODULE__{}, attrs) do
    schema
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:eligibility_at, ParticipantPolicy.valid_eligibility_options())
    |> validate_number(:min_age_months, greater_than_or_equal_to: 0)
    |> validate_number(:max_age_months, greater_than_or_equal_to: 0)
    |> validate_number(:min_grade, greater_than_or_equal_to: 1, less_than_or_equal_to: 13)
    |> validate_number(:max_grade, greater_than_or_equal_to: 1, less_than_or_equal_to: 13)
    |> validate_allowed_genders()
    |> validate_age_range()
    |> validate_grade_range()
    |> unique_constraint(:program_id)
    |> check_constraint(:eligibility_at, name: :valid_eligibility_at)
    |> check_constraint(:min_age_months, name: :valid_age_range)
    |> check_constraint(:min_grade, name: :valid_grade_range)
    |> check_constraint(:min_age_months, name: :valid_age_months)
    |> check_constraint(:min_grade, name: :valid_grade_bounds)
  end

  defp validate_allowed_genders(changeset) do
    case get_field(changeset, :allowed_genders) do
      nil ->
        changeset

      genders when is_list(genders) ->
        invalid = Enum.reject(genders, &(&1 in ParticipantPolicy.valid_genders()))

        if invalid == [] do
          changeset
        else
          add_error(
            changeset,
            :allowed_genders,
            "contains invalid values: #{Enum.join(invalid, ", ")}"
          )
        end

      _ ->
        add_error(changeset, :allowed_genders, "must be a list")
    end
  end

  defp validate_age_range(changeset) do
    min = get_field(changeset, :min_age_months)
    max = get_field(changeset, :max_age_months)

    if is_integer(min) and is_integer(max) and min > max do
      add_error(changeset, :min_age_months, "must not exceed maximum age")
    else
      changeset
    end
  end

  defp validate_grade_range(changeset) do
    min = get_field(changeset, :min_grade)
    max = get_field(changeset, :max_grade)

    if is_integer(min) and is_integer(max) and min > max do
      add_error(changeset, :min_grade, "must not exceed maximum grade")
    else
      changeset
    end
  end
end
