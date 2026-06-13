defmodule KlassHero.Family.Domain.Models.Child do
  @moduledoc """
  Child domain entity representing a child in the Family bounded context.

  This is a pure domain model with no persistence or infrastructure concerns.
  Validation happens at the use case boundary via Ecto changesets.

  Guardian relationships are managed through the children_guardians join table,
  not through a direct parent_id reference on the child.

  ## Fields

  - `id` - Unique identifier for the child
  - `first_name` - Child's first name
  - `last_name` - Child's last name
  - `date_of_birth` - Child's birth date
  - `gender` - Child's gender ("male", "female", "diverse", "not_specified")
  - `school_grade` - Current school grade (1-13), nil if not applicable
  - `emergency_contact` - Optional emergency contact info
  - `support_needs` - Optional support needs or accommodations
  - `allergies` - Optional allergy information
  - `school_name` - Name of the child's school (optional)
  - `inserted_at` - When the record was created
  - `updated_at` - When the record was last updated
  """

  use KlassHero.Shared.Domain.Models.PersistenceSupport

  @valid_genders ~w(male female diverse not_specified)

  @enforce_keys [:id, :first_name, :last_name, :date_of_birth]
  defstruct [
    :id,
    :first_name,
    :last_name,
    :date_of_birth,
    :emergency_contact,
    :support_needs,
    :allergies,
    :inserted_at,
    :updated_at,
    gender: "not_specified",
    school_grade: nil,
    school_name: nil
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          first_name: String.t(),
          last_name: String.t(),
          date_of_birth: Date.t(),
          gender: String.t(),
          school_grade: non_neg_integer() | nil,
          emergency_contact: String.t() | nil,
          support_needs: String.t() | nil,
          allergies: String.t() | nil,
          school_name: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc "Returns the list of valid gender values."
  @spec valid_genders() :: [String.t()]
  def valid_genders, do: @valid_genders

  @doc """
  Returns the full name of the child (first name + last name).

  ## Examples

      iex> child = %Child{first_name: "Alice", last_name: "Smith", ...}
      iex> Child.full_name(child)
      "Alice Smith"
  """
  def full_name(%__MODULE__{first_name: first_name, last_name: last_name}) do
    "#{first_name} #{last_name}"
  end

  @doc """
  Returns the canonical anonymized attribute values for GDPR account deletion.

  The domain model owns the definition of what "anonymized" means for a child,
  keeping this business decision out of persistence adapters.
  """
  def anonymized_attrs do
    %{
      first_name: "Anonymized",
      last_name: "Child",
      date_of_birth: nil,
      emergency_contact: nil,
      support_needs: nil,
      allergies: nil,
      school_name: nil,
      school_grade: nil
    }
  end

  @doc """
  Creates a new Child with validation.

  Business Rules:
  - first_name must be present and non-empty
  - last_name must be present and non-empty
  - date_of_birth must be present and not in the future

  Returns:
  - `{:ok, child}` if all validations pass
  - `{:error, [reasons]}` with list of validation errors
  """
  def new(attrs) do
    child = struct!(__MODULE__, attrs)

    # nil overrides the struct default; normalize back to "not_specified".
    child = %{child | gender: child.gender || "not_specified"}

    case validate(child) do
      [] -> {:ok, child}
      errors -> {:error, errors}
    end
  end

  @doc "Computes age in whole months from date_of_birth to reference_date."
  @spec age_in_months(t(), Date.t()) :: non_neg_integer()
  def age_in_months(%__MODULE__{date_of_birth: dob}, reference_date) do
    year_months = (reference_date.year - dob.year) * 12
    month_diff = reference_date.month - dob.month

    # Subtract one month if reference day < birth day (birthday not yet reached this month).
    day_adjustment = if reference_date.day < dob.day, do: -1, else: 0

    max(year_months + month_diff + day_adjustment, 0)
  end

  @doc """
  Validates that a child struct has valid business rules.
  """
  def valid?(%__MODULE__{} = child) do
    validate(child) == []
  end

  defp validate(%__MODULE__{} = child) do
    []
    |> validate_first_name(child.first_name)
    |> validate_last_name(child.last_name)
    |> validate_date_of_birth(child.date_of_birth)
    |> validate_gender(child.gender)
    |> validate_school_grade(child.school_grade)
  end

  defp validate_first_name(errors, first_name) when is_binary(first_name) do
    trimmed = String.trim(first_name)

    if trimmed == "" do
      ["First name cannot be empty" | errors]
    else
      errors
    end
  end

  defp validate_first_name(errors, _), do: ["First name must be a string" | errors]

  defp validate_last_name(errors, last_name) when is_binary(last_name) do
    trimmed = String.trim(last_name)

    if trimmed == "" do
      ["Last name cannot be empty" | errors]
    else
      errors
    end
  end

  defp validate_last_name(errors, _), do: ["Last name must be a string" | errors]

  defp validate_date_of_birth(errors, %Date{} = date) do
    if Date.after?(date, Date.utc_today()) do
      ["Date of birth cannot be in the future" | errors]
    else
      errors
    end
  end

  defp validate_date_of_birth(errors, _), do: ["Date of birth must be a date" | errors]

  defp validate_gender(errors, gender) when gender in @valid_genders, do: errors

  defp validate_gender(errors, _), do: ["Gender must be one of: #{Enum.join(@valid_genders, ", ")}" | errors]

  defp validate_school_grade(errors, nil), do: errors

  defp validate_school_grade(errors, grade) when is_integer(grade) and grade >= 1 and grade <= 13, do: errors

  defp validate_school_grade(errors, _), do: ["School grade must be between 1 and 13" | errors]
end
