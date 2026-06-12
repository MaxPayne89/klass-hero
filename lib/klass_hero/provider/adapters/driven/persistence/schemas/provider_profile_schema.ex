defmodule KlassHero.Provider.Adapters.Driven.Persistence.Schemas.ProviderProfileSchema do
  @moduledoc """
  Ecto schema for the providers table.

  This is an infrastructure adapter that maps database records to Ecto structs.
  Use ProviderProfileMapper to convert between ProviderProfileSchema and domain ProviderProfile entities.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "providers" do
    field :identity_id, :binary_id
    field :business_name, :string
    field :business_owner_email, :string
    field :description, :string
    field :phone, :string
    field :website, :string
    field :address, :string
    field :logo_url, :string
    field :verified, :boolean, default: false
    field :verified_at, :utc_datetime
    field :categories, {:array, :string}, default: []
    field :profile_status, :string, default: "active"

    belongs_to :verified_by, User, type: :binary_id

    timestamps()
  end

  @doc """
  Creates a changeset for validation.

  Required fields:
  - identity_id (must be a valid UUID)
  - business_name (1-200 characters)

  Optional fields:
  - description (1-1000 characters if provided)
  - phone (1-20 characters if provided)
  - website (1-500 characters if provided, must start with https://)
  - address (1-500 characters if provided)
  - logo_url (1-500 characters if provided)
  - verified (boolean, defaults to false)
  - verified_at (DateTime if provided)
  - categories (list of strings, defaults to [])
  """
  def changeset(provider_profile_schema, attrs) do
    provider_profile_schema
    |> cast(attrs, [
      :identity_id,
      :business_name,
      :business_owner_email,
      :description,
      :phone,
      :website,
      :address,
      :logo_url,
      :verified,
      :verified_at,
      :verified_by_id,
      :categories,
      :profile_status
    ])
    |> validate_required([:identity_id, :business_name])
    |> validate_inclusion(:profile_status, ~w(draft active))
    |> validate_profile_fields()
    |> validate_length(:logo_url, min: 1, max: 500)
    |> unique_constraint(:identity_id,
      name: :providers_identity_id_index,
      message: "Provider profile already exists for this identity"
    )
  end

  @doc """
  Form changeset for provider profile editing via LiveView.

  Only casts `:description` — logo_url is set programmatically after upload,
  and other fields (business_name, phone, etc.) are not editable in this form.
  """
  def edit_changeset(schema, attrs) do
    schema
    |> cast(attrs, [:description])
    |> validate_length(:description, max: 1000)
  end

  @doc """
  Form changeset for provider profile completion by staff-invite providers.

  Casts all fields a provider needs to fill during profile completion:
  business_name, description, phone, website, address, categories.
  Logo URL is set programmatically after upload (not in this changeset).
  """
  @completion_fields ~w(business_name description phone website address categories)a

  def completion_changeset(schema, attrs) do
    schema
    |> cast(attrs, @completion_fields)
    |> validate_required([:business_name, :description])
    |> validate_profile_fields()
  end

  @doc """
  Admin changeset for provider profile management via Backpex.

  Casts `verified` — provider-owned fields
  (business_name, description, phone, etc.) are excluded.

  When `verified` changes, also sets `verified_at` and `verified_by_id`
  to maintain consistency with the domain model's verify/unverify behaviour.

  Accepts 3 args to match the Backpex changeset callback signature.
  The metadata keyword list includes `:assigns` with the current admin scope.
  """
  def admin_changeset(schema, attrs, metadata) do
    schema
    |> cast(attrs, [:verified])
    |> maybe_set_verification_fields(metadata)
  end

  # Trigger: admin toggled the `verified` checkbox in the Backpex form
  # Why: verified_at and verified_by_id must stay in sync with verified flag,
  #      matching what VerifyProvider / UnverifyProvider use cases set
  # Outcome: DB record has consistent audit trail after Backpex save
  defp maybe_set_verification_fields(changeset, metadata) do
    case get_change(changeset, :verified) do
      true ->
        admin_id = metadata[:assigns].current_scope.user.id

        changeset
        |> put_change(:verified_at, DateTime.utc_now() |> DateTime.truncate(:second))
        |> put_change(:verified_by_id, admin_id)

      false ->
        changeset
        |> put_change(:verified_at, nil)
        |> put_change(:verified_by_id, nil)

      nil ->
        changeset
    end
  end

  defp validate_profile_fields(changeset) do
    changeset
    |> validate_length(:business_name, min: 1, max: 200)
    |> validate_length(:description, min: 1, max: 1000)
    |> validate_length(:phone, min: 1, max: 20)
    |> validate_length(:website, min: 1, max: 500)
    |> validate_website_protocol()
    |> validate_length(:address, min: 1, max: 500)
  end

  defp validate_website_protocol(changeset) do
    case get_change(changeset, :website) do
      nil ->
        changeset

      website when is_binary(website) ->
        if String.starts_with?(website, "https://") do
          changeset
        else
          add_error(changeset, :website, "must start with https://")
        end

      _ ->
        changeset
    end
  end
end
