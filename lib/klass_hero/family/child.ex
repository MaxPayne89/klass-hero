defmodule KlassHero.Family.Child do
  @moduledoc """
  A child in the Family context.

  This is the conventional Phoenix model: the Ecto schema *is* the domain
  struct. Validation lives in the changeset (the single gatekeeper); pure,
  side-effect-free helpers (`full_name/1`, `age_in_months/2`) make up the
  functional core. All persistence happens in `KlassHero.Family`.

  Guardian relationships are managed through the `children_guardians` join
  table (`KlassHero.Family.ChildGuardian`), not a direct `parent_id`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @valid_genders ~w(male female diverse not_specified)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "children" do
    field :first_name, :string
    field :last_name, :string
    field :date_of_birth, :date
    field :gender, :string, default: "not_specified"
    field :school_grade, :integer
    field :emergency_contact, :string
    field :support_needs, :string
    field :allergies, :string
    field :school_name, :string

    timestamps()
  end

  @castable_fields [
    :first_name,
    :last_name,
    :date_of_birth,
    :gender,
    :school_grade,
    :emergency_contact,
    :support_needs,
    :allergies,
    :school_name
  ]

  @doc """
  Changeset for creating, updating, and form-tracking a child.

  ## Validations

  - Required: `first_name`, `last_name`, `date_of_birth`
  - `first_name` / `last_name`: 1–100 characters
  - `date_of_birth`: must be in the past
  - `gender`: one of #{inspect(@valid_genders)}
  - `school_grade`: 1–13 when present
  """
  def changeset(child, attrs) do
    child
    |> cast(attrs, @castable_fields)
    |> validate_required([:first_name, :last_name, :date_of_birth])
    |> validate_length(:first_name, min: 1, max: 100)
    |> validate_length(:last_name, min: 1, max: 100)
    |> validate_length(:emergency_contact, max: 255)
    |> validate_length(:school_name, max: 255)
    |> validate_date_in_past(:date_of_birth)
    |> validate_inclusion(:gender, @valid_genders)
    |> validate_number(:school_grade, greater_than_or_equal_to: 1, less_than_or_equal_to: 13)
    |> check_constraint(:gender, name: :valid_gender)
    |> check_constraint(:school_grade, name: :valid_school_grade)
  end

  @doc """
  Changeset for anonymizing a child during GDPR account deletion.

  Receives the canonical anonymized values from `anonymized_attrs/0` and
  applies them mechanically.
  """
  def anonymize_changeset(%__MODULE__{} = child, anonymized_attrs) when is_map(anonymized_attrs) do
    change(child, anonymized_attrs)
  end

  @doc "The valid gender values."
  def valid_genders, do: @valid_genders

  @doc """
  The canonical anonymized attribute values for GDPR account deletion.

  The model owns what "anonymized" means for a child, keeping that decision
  out of the persistence path.
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

  @doc "The child's full name."
  def full_name(%__MODULE__{first_name: first_name, last_name: last_name}) do
    "#{first_name} #{last_name}"
  end

  @doc "Age in whole months from `date_of_birth` to `reference_date`."
  @spec age_in_months(t(), Date.t()) :: non_neg_integer()
  def age_in_months(%__MODULE__{date_of_birth: dob}, reference_date) do
    year_months = (reference_date.year - dob.year) * 12
    month_diff = reference_date.month - dob.month

    # Subtract one month if the birthday hasn't been reached yet this month.
    day_adjustment = if reference_date.day < dob.day, do: -1, else: 0

    max(year_months + month_diff + day_adjustment, 0)
  end

  defp validate_date_in_past(changeset, field) do
    validate_change(changeset, field, fn ^field, date ->
      case Date.compare(date, Date.utc_today()) do
        :lt -> []
        _ -> [{field, "must be in the past"}]
      end
    end)
  end

  @type t :: %__MODULE__{
          id: binary() | nil,
          first_name: String.t() | nil,
          last_name: String.t() | nil,
          date_of_birth: Date.t() | nil,
          gender: String.t(),
          school_grade: non_neg_integer() | nil,
          emergency_contact: String.t() | nil,
          support_needs: String.t() | nil,
          allergies: String.t() | nil,
          school_name: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }
end
