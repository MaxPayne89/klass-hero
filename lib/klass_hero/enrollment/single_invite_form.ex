defmodule KlassHero.Enrollment.SingleInviteForm do
  @moduledoc """
  Schemaless embedded form backing the provider's manual single-invite
  LiveView. Delegates field-shape validations to
  `InviteFieldValidations` so the form can't drift from the persistence
  schema's rules.

  The form carries `program_id` directly (UI picks from a dropdown of the
  provider's programs). Ownership of the chosen program is re-checked at
  the command layer.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.Enrollment.Domain.Services.InviteFieldValidations

  @primary_key false
  embedded_schema do
    field :program_id, :binary_id
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
  end

  @required_fields ~w(program_id child_first_name child_last_name child_date_of_birth guardian_email)a

  @optional_fields ~w(
    guardian_first_name guardian_last_name
    guardian2_email guardian2_first_name guardian2_last_name
    school_grade school_name medical_conditions nut_allergy
    consent_photo_marketing consent_photo_social_media
  )a

  @type t :: %__MODULE__{}

  @spec changeset(t() | map(), map()) :: Ecto.Changeset.t()
  def changeset(form \\ %__MODULE__{}, attrs) do
    form
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> InviteFieldValidations.apply()
  end

  @doc """
  Converts a valid changeset to the attribute map the persistence layer
  expects. `provider_id` is set to nil here — the command layer is the
  only trust-boundary that can bind it from the current scope.
  """
  @spec to_invite_row(Ecto.Changeset.t()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def to_invite_row(%Ecto.Changeset{valid?: true} = changeset) do
    row =
      changeset
      |> apply_changes()
      |> Map.from_struct()
      |> Map.put(:provider_id, nil)

    {:ok, row}
  end

  def to_invite_row(%Ecto.Changeset{} = changeset), do: {:error, changeset}

  @doc """
  Merges domain-layer field errors returned by the command back into a
  changeset, with `:action` pre-set so `<.input>` renders them.
  """
  @spec apply_domain_errors(Ecto.Changeset.t(), [{atom(), String.t()}]) :: Ecto.Changeset.t()
  def apply_domain_errors(%Ecto.Changeset{} = changeset, field_errors) when is_list(field_errors) do
    field_errors
    |> Enum.reduce(changeset, fn {field, msg}, acc -> add_error(acc, field, msg) end)
    |> Map.put(:action, :validate)
  end
end
