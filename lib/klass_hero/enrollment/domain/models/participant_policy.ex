defmodule KlassHero.Enrollment.Domain.Models.ParticipantPolicy do
  @moduledoc """
  Domain model representing participant eligibility restrictions for a program.

  Owned by the Enrollment context. Providers configure age, gender, and grade
  restrictions; the enrollment context enforces these during enrollment.

  ## Restriction Semantics

  - `min_age_months` / `max_age_months` — age range in total months. nil = no bound.
  - `allowed_genders` — list of allowed gender values. Empty list = no restriction.
  - `min_grade` / `max_grade` — school grade range (Klasse 1-13). nil = no bound.
  - `eligibility_at` — when to evaluate: "registration" (today) or "program_start".
  """

  @enforce_keys [:program_id]

  defstruct [
    :id,
    :program_id,
    :min_age_months,
    :max_age_months,
    :min_grade,
    :max_grade,
    :inserted_at,
    :updated_at,
    eligibility_at: "registration",
    allowed_genders: []
  ]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          program_id: String.t(),
          min_age_months: non_neg_integer() | nil,
          max_age_months: non_neg_integer() | nil,
          allowed_genders: [String.t()],
          min_grade: pos_integer() | nil,
          max_grade: pos_integer() | nil,
          eligibility_at: String.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @valid_genders ~w(male female diverse not_specified)
  @valid_eligibility ~w(registration program_start)

  def valid_genders, do: @valid_genders
  def valid_eligibility_options, do: @valid_eligibility

  @doc """
  Creates a new ParticipantPolicy from the given attributes.

  Returns `{:ok, policy}` on success or `{:error, errors}` with a list
  of human-readable validation messages.

  Normalizes nil `allowed_genders` to `[]` and nil `eligibility_at` to `"registration"`.
  """
  @spec new(map()) :: {:ok, t()} | {:error, [String.t()]}
  def new(attrs) when is_map(attrs) do
    allowed_genders = attrs[:allowed_genders] || []
    eligibility_at = attrs[:eligibility_at] || "registration"

    errors =
      []
      |> validate_program_id(attrs[:program_id])
      |> validate_age_range(attrs[:min_age_months], attrs[:max_age_months])
      |> validate_grade_range(attrs[:min_grade], attrs[:max_grade])
      |> validate_genders(allowed_genders)
      |> validate_eligibility_at(eligibility_at)

    if errors == [] do
      {:ok,
       %__MODULE__{
         id: attrs[:id],
         program_id: attrs[:program_id],
         min_age_months: attrs[:min_age_months],
         max_age_months: attrs[:max_age_months],
         allowed_genders: allowed_genders,
         min_grade: attrs[:min_grade],
         max_grade: attrs[:max_grade],
         eligibility_at: eligibility_at,
         inserted_at: attrs[:inserted_at],
         updated_at: attrs[:updated_at]
       }}
    else
      {:error, errors}
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

  defp validate_program_id(errors, id) when is_binary(id) and byte_size(id) > 0, do: errors
  defp validate_program_id(errors, _), do: ["program ID is required" | errors]

  defp validate_age_range(errors, min, max) when is_integer(min) and is_integer(max) and min > max do
    ["minimum age must not exceed maximum age" | errors]
  end

  defp validate_age_range(errors, _min, _max), do: errors

  defp validate_grade_range(errors, min, max) when is_integer(min) and is_integer(max) and min > max do
    ["minimum grade must not exceed maximum grade" | errors]
  end

  defp validate_grade_range(errors, _min, _max), do: errors

  defp validate_genders(errors, genders) when is_list(genders) do
    invalid = Enum.reject(genders, &(&1 in @valid_genders))

    if invalid == [] do
      errors
    else
      [
        "invalid gender values: #{Enum.join(invalid, ", ")}; allowed: #{Enum.join(@valid_genders, ", ")}"
        | errors
      ]
    end
  end

  defp validate_genders(errors, _), do: errors

  defp validate_eligibility_at(errors, value) when value in @valid_eligibility, do: errors

  defp validate_eligibility_at(errors, value) do
    [
      "invalid eligibility_at value: #{inspect(value)}; allowed: #{Enum.join(@valid_eligibility, ", ")}"
      | errors
    ]
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
