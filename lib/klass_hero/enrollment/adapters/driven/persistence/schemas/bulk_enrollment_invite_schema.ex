defmodule KlassHero.Enrollment.Adapters.Driven.Persistence.Schemas.BulkEnrollmentInviteSchema do
  @moduledoc """
  Ecto schema for the bulk_enrollment_invites table.

  Stores denormalized CSV data as a staging record for bulk enrollment.
  When a parent acts on the invite, real domain entities (User, ParentProfile,
  Child, Enrollment, Consents) are created from this data.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.Enrollment.Domain.Services.InviteFieldValidations

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  @statuses [:pending, :invite_sent, :registered, :enrolled, :failed]

  schema "bulk_enrollment_invites" do
    field :program_id, :binary_id
    field :provider_id, :binary_id
    field :child_first_name, :string
    field :child_last_name, :string
    field :child_date_of_birth, :date
    field :guardian_email, :string
    field :guardian_first_name, :string
    field :guardian_last_name, :string
    field :guardian2_email, :string
    field :guardian2_first_name, :string
    field :guardian2_last_name, :string
    field :school_grade, :integer
    field :school_name, :string
    field :medical_conditions, :string
    field :nut_allergy, :boolean, default: false
    field :consent_photo_marketing, :boolean, default: false
    field :consent_photo_social_media, :boolean, default: false
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :invite_token, :string
    field :invite_sent_at, :utc_datetime
    field :registered_at, :utc_datetime
    field :enrolled_at, :utc_datetime
    field :enrollment_id, :binary_id
    field :error_details, :string

    timestamps()
  end

  @required_fields ~w(program_id provider_id child_first_name child_last_name child_date_of_birth guardian_email)a

  @optional_fields ~w(
    guardian_first_name guardian_last_name
    guardian2_email guardian2_first_name guardian2_last_name
    school_grade school_name medical_conditions nut_allergy
    consent_photo_marketing consent_photo_social_media
    status invite_token invite_sent_at registered_at enrolled_at
    enrollment_id error_details
  )a

  @import_fields ~w(
    program_id provider_id child_first_name child_last_name child_date_of_birth
    guardian_email guardian_first_name guardian_last_name
    guardian2_email guardian2_first_name guardian2_last_name
    school_grade school_name medical_conditions nut_allergy
    consent_photo_marketing consent_photo_social_media
  )a

  @valid_transitions %{
    pending: [:invite_sent, :failed],
    invite_sent: [:registered, :failed],
    registered: [:enrolled, :failed],
    enrolled: [],
    failed: [:pending]
  }

  @lifecycle_fields ~w(
    status invite_token invite_sent_at registered_at enrolled_at
    enrollment_id error_details
  )a

  def changeset(schema \\ %__MODULE__{}, attrs) do
    schema
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> InviteFieldValidations.apply()
    |> unique_constraint([:program_id, :guardian_email, :child_first_name, :child_last_name],
      name: :bulk_invites_program_guardian_child_unique
    )
    |> unique_constraint(:invite_token)
    |> foreign_key_constraint(:program_id)
    |> foreign_key_constraint(:provider_id)
    |> foreign_key_constraint(:enrollment_id)
    |> check_constraint(:status, name: :valid_status)
    |> check_constraint(:school_grade, name: :valid_school_grade)
  end

  def valid_transitions, do: @valid_transitions

  @doc """
  Changeset for creating invite records from CSV import data.

  Only accepts fields from the CSV. Status defaults to "pending".
  Lifecycle fields (invite_token, timestamps, enrollment_id, error_details)
  are managed via transition_changeset/2.
  """
  def import_changeset(schema \\ %__MODULE__{}, attrs) do
    schema
    |> cast(attrs, @import_fields)
    |> validate_required(@required_fields)
    |> InviteFieldValidations.apply()
    |> unique_constraint([:program_id, :guardian_email, :child_first_name, :child_last_name],
      name: :bulk_invites_program_guardian_child_unique
    )
    |> foreign_key_constraint(:program_id)
    |> foreign_key_constraint(:provider_id)
    |> check_constraint(:school_grade, name: :valid_school_grade)
  end

  @doc """
  Changeset for transitioning invite status.

  Validates that the transition from current status to target status
  is legal per the state machine. Also casts lifecycle fields.
  """
  def transition_changeset(%__MODULE__{} = schema, attrs) do
    schema
    |> cast(attrs, @lifecycle_fields)
    |> validate_required([:status])
    |> validate_status_transition()
    |> unique_constraint(:invite_token)
    |> foreign_key_constraint(:enrollment_id)
    |> check_constraint(:status, name: :valid_status)
  end

  defp validate_status_transition(changeset) do
    case {changeset.data.status, get_change(changeset, :status)} do
      {_current, nil} ->
        add_error(changeset, :status, "status change is required for transitions")

      {current, target} ->
        allowed = Map.get(@valid_transitions, current, [])

        if target in allowed do
          changeset
        else
          add_error(changeset, :status, "cannot transition from #{current} to #{target}",
            validation: :status_transition,
            from: current,
            to: target
          )
        end
    end
  end
end
