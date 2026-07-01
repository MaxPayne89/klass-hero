defmodule KlassHero.Enrollment.ParticipantPolicy do
  @moduledoc """
  Participant eligibility restrictions for a program (`participant_policies` table).

  Owned by the Enrollment context. Providers configure age, gender, and grade
  restrictions; the context enforces them during enrollment.

  This module is both the Ecto schema and the struct consumers pattern-match.
  The changeset is the single validation gatekeeper; `eligible?/2` and
  `age_in_months/2` are the functional core for eligibility checks.

  ## Restriction Semantics

  - `min_age_months` / `max_age_months` — age range in total months. nil = no bound.
  - `allowed_genders` — list of allowed gender values. Empty list = no restriction.
  - `min_grade` / `max_grade` — school grade range (Klasse 1-13). nil = no bound.
  - `eligibility_at` — when to evaluate: "registration" (today) or "program_start".
  """

  use Ecto.Schema

  import Ecto.Changeset

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

  @type t :: %__MODULE__{}

  @valid_genders ~w(male female diverse not_specified)
  @valid_eligibility ~w(registration program_start)

  def valid_genders, do: @valid_genders
  def valid_eligibility_options, do: @valid_eligibility

  @required_fields ~w(program_id)a
  @optional_fields ~w(eligibility_at min_age_months max_age_months allowed_genders min_grade max_grade)a

  @doc """
  Changeset for participant policy creation or update.

  All restriction fields are optional; DB constraints enforce range validity
  and uniqueness per program.
  """
  def changeset(schema \\ %__MODULE__{}, attrs) do
    schema
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:eligibility_at, @valid_eligibility)
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
        invalid = Enum.reject(genders, &(&1 in @valid_genders))

        if invalid == [] do
          changeset
        else
          add_error(changeset, :allowed_genders, "contains invalid values: #{Enum.join(invalid, ", ")}")
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

  @doc """
  Checks whether a participant meets the policy restrictions.

  The participant map must contain `age_months`, `gender`, and `grade` keys.
  Returns `{:ok, :eligible}` or `{:error, reasons}` with all failing reasons.
  """
  @spec eligible?(t(), map()) :: {:ok, :eligible} | {:error, [String.t()]}
  def eligible?(%__MODULE__{} = policy, %{age_months: _, gender: _, grade: _} = participant) do
    reasons =
      []
      |> check_age(policy, participant.age_months)
      |> check_gender(policy, participant.gender)
      |> check_grade(policy, participant.grade)

    if reasons == [] do
      {:ok, :eligible}
    else
      {:error, reasons}
    end
  end

  @doc """
  Computes age in complete months between date_of_birth and reference_date.

  Subtracts one month if the day-of-month hasn't been reached yet,
  ensuring accurate whole-month age calculation.
  """
  @spec age_in_months(Date.t(), Date.t()) :: non_neg_integer()
  def age_in_months(date_of_birth, reference_date) do
    year_months = (reference_date.year - date_of_birth.year) * 12
    month_diff = reference_date.month - date_of_birth.month

    # Subtract one month if birthday hasn't occurred yet this month
    day_adjustment = if reference_date.day < date_of_birth.day, do: -1, else: 0

    max(year_months + month_diff + day_adjustment, 0)
  end

  defp check_age(reasons, %{min_age_months: min, max_age_months: max}, age_months) do
    reasons
    |> maybe_check_min_age(min, age_months)
    |> maybe_check_max_age(max, age_months)
  end

  defp maybe_check_min_age(reasons, nil, _age_months), do: reasons

  defp maybe_check_min_age(reasons, min, age_months) when age_months < min do
    ["child is too young (minimum age: #{min} months)" | reasons]
  end

  defp maybe_check_min_age(reasons, _min, _age_months), do: reasons

  defp maybe_check_max_age(reasons, nil, _age_months), do: reasons

  defp maybe_check_max_age(reasons, max, age_months) when age_months > max do
    ["child is too old (maximum age: #{max} months)" | reasons]
  end

  defp maybe_check_max_age(reasons, _max, _age_months), do: reasons

  defp check_gender(reasons, %{allowed_genders: []}, _gender), do: reasons

  defp check_gender(reasons, %{allowed_genders: allowed}, gender) do
    if gender in allowed do
      reasons
    else
      ["gender not allowed for this program (allowed: #{Enum.join(allowed, ", ")})" | reasons]
    end
  end

  defp check_grade(reasons, %{min_grade: nil, max_grade: nil}, _grade), do: reasons

  defp check_grade(reasons, _policy, nil) do
    ["school grade is required for this program" | reasons]
  end

  defp check_grade(reasons, %{min_grade: min, max_grade: max}, grade) do
    reasons
    |> maybe_check_min_grade(min, grade)
    |> maybe_check_max_grade(max, grade)
  end

  defp maybe_check_min_grade(reasons, nil, _grade), do: reasons

  defp maybe_check_min_grade(reasons, min, grade) when grade < min do
    ["school grade too low (minimum: grade #{min})" | reasons]
  end

  defp maybe_check_min_grade(reasons, _min, _grade), do: reasons

  defp maybe_check_max_grade(reasons, nil, _grade), do: reasons

  defp maybe_check_max_grade(reasons, max, grade) when grade > max do
    ["school grade too high (maximum: grade #{max})" | reasons]
  end

  defp maybe_check_max_grade(reasons, _max, _grade), do: reasons
end
