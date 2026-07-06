defmodule KlassHero.Enrollment.ParticipantPolicyForm do
  @moduledoc """
  Schemaless form for participant policy validation.

  Provides a clean domain-level changeset for the provider dashboard form
  without exposing Ecto persistence schemas through the public facade.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.Enrollment.ParticipantPolicy

  @primary_key false
  embedded_schema do
    field :eligibility_at, :string, default: "registration"
    field :min_age_months, :integer
    field :max_age_months, :integer
    field :allowed_genders, {:array, :string}, default: []
    field :min_grade, :integer
    field :max_grade, :integer
  end

  @optional_fields ~w(eligibility_at min_age_months max_age_months allowed_genders min_grade max_grade)a

  @doc """
  Returns a changeset for participant policy form validation.
  """
  def changeset(form \\ %__MODULE__{}, attrs) do
    form
    |> cast(attrs, @optional_fields)
    |> validate_inclusion(:eligibility_at, ParticipantPolicy.valid_eligibility_options())
    |> validate_number(:min_age_months, greater_than_or_equal_to: 0)
    |> validate_number(:max_age_months, greater_than_or_equal_to: 0)
    |> validate_number(:min_grade, greater_than_or_equal_to: 1, less_than_or_equal_to: 13)
    |> validate_number(:max_grade, greater_than_or_equal_to: 1, less_than_or_equal_to: 13)
    |> validate_allowed_genders()
    |> validate_age_range()
    |> validate_grade_range()
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
