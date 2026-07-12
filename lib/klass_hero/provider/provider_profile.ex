defmodule KlassHero.Provider.ProviderProfile do
  @moduledoc """
  Provider profile (`providers` table) — the aggregate root of the Provider context.

  A profile is created in `:draft` status during a deliberate staff→provider
  upgrade (ADR-0005) and completed to `:active` once business details are filled
  in. Admins verify/unverify providers, which drives cross-context projections
  (VerifiedProviders, ProgramListings) via integration events published by the
  context facade.

  This module is both the Ecto schema and the struct consumers pattern-match.
  Two layers guard invariants:

  - The **changesets** (`changeset/2`, `edit_changeset/2`, `completion_changeset/2`,
    `admin_changeset/3`) are the persistence-boundary gatekeepers.
  - The pure **functional core** (`new/1`, `verify/2`, `unverify/1`,
    `complete_profile/2`, predicates) enforces domain rules and returns
    string-list validation errors, preserving the frozen `{:validation_error, _}`
    contract the facade exposes.

  Providers link to the Accounts context by correlation id (`identity_id`), not a
  foreign key, preserving bounded-context independence.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  @profile_statuses [:draft, :active]
  @entity_types [:individual, :business]

  schema "providers" do
    field :identity_id, :binary_id
    field :entity_type, Ecto.Enum, values: @entity_types, default: :individual
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
    field :profile_status, Ecto.Enum, values: @profile_statuses, default: :active

    belongs_to :verified_by, User, type: :binary_id

    timestamps()
  end

  @type t :: %__MODULE__{}

  @doc "Returns the list of valid profile statuses."
  @spec valid_profile_statuses() :: [:draft | :active]
  def valid_profile_statuses, do: @profile_statuses

  # ── Changesets (persistence-boundary gatekeepers) ──────────────────────────

  @doc "Changeset for insert/update of a provider profile."
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [
      :identity_id,
      :entity_type,
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
  @completion_cast_fields ~w(business_name description phone website address categories entity_type)a

  def completion_changeset(schema, attrs) do
    schema
    |> cast(attrs, @completion_cast_fields)
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

  # Keeps verified_at and verified_by_id in sync with verified flag (audit trail).
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

  # ── Functional core (pure domain rules) ────────────────────────────────────

  @doc """
  Builds and validates a provider profile struct from attrs.

  Returns `{:ok, t()}` or `{:error, [message]}` — the string-list error the
  facade wraps into `{:error, {:validation_error, errors}}`.
  """
  @spec new(map()) :: {:ok, t()} | {:error, [String.t()]}
  def new(attrs) do
    profile = struct!(__MODULE__, apply_defaults(attrs))

    case validate(profile) do
      [] -> {:ok, profile}
      errors -> {:error, errors}
    end
  end

  defp apply_defaults(attrs) do
    attrs
    |> Map.put_new(:verified, false)
    |> Map.put_new(:categories, [])
    |> Map.put_new(:profile_status, :active)
  end

  @doc "Returns true when the profile passes all domain validations."
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{} = profile), do: validate(profile) == []

  @doc "Checks if the provider has been verified."
  @spec verified?(t()) :: boolean()
  def verified?(%__MODULE__{verified: true}), do: true
  def verified?(_), do: false

  @doc "Returns true if the profile is in draft status (needs completion)."
  @spec draft?(t()) :: boolean()
  def draft?(%__MODULE__{profile_status: :draft}), do: true
  def draft?(_), do: false

  @doc """
  Marks a provider profile as verified by an admin.

  Records the admin who performed the verification and the timestamp.
  Idempotent — verifying an already-verified provider updates the audit trail.
  """
  @spec verify(t(), String.t() | nil) :: {:ok, t()}
  def verify(%__MODULE__{} = profile, admin_id) when is_binary(admin_id) or is_nil(admin_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, %{profile | verified: true, verified_at: now, verified_by_id: admin_id, updated_at: now}}
  end

  @doc """
  Revokes verification from a provider profile.

  Clears the verified flag, timestamp, and admin audit trail.
  Idempotent — unverifying an already-unverified provider succeeds.
  """
  @spec unverify(t()) :: {:ok, t()}
  def unverify(%__MODULE__{} = profile) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    {:ok, %{profile | verified: false, verified_at: nil, verified_by_id: nil, updated_at: now}}
  end

  @doc """
  Completes a draft provider profile with the given fields.

  Only allowed when profile_status is :draft. Sets status to :active.

  Returns:
  - `{:ok, t()}` on success
  - `{:error, :already_active}` if profile_status is not :draft
  - `{:error, [message]}` if validation fails
  """
  @completion_fields ~w(business_name description phone website address logo_url categories entity_type)a

  @spec complete_profile(t(), map()) :: {:ok, t()} | {:error, :already_active | [String.t()]}
  def complete_profile(%__MODULE__{profile_status: :draft} = profile, attrs) when is_map(attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    updated =
      profile
      |> struct(Map.take(attrs, @completion_fields))
      |> Map.put(:profile_status, :active)
      |> Map.put(:updated_at, now)

    case validate(updated) do
      [] -> {:ok, updated}
      errors -> {:error, errors}
    end
  end

  def complete_profile(%__MODULE__{profile_status: :active}, _attrs), do: {:error, :already_active}

  # ── Pure validation pipeline (drives new/1 and complete_profile/2) ──────────

  defp validate(%__MODULE__{} = profile) do
    []
    |> validate_identity_id(profile.identity_id)
    |> validate_business_name(profile.business_name)
    |> validate_description(profile.description)
    |> validate_phone(profile.phone)
    |> validate_website(profile.website)
    |> validate_address(profile.address)
    |> validate_logo_url(profile.logo_url)
    |> validate_verified(profile.verified)
    |> validate_verified_at(profile.verified_at)
    |> validate_categories(profile.categories)
    |> validate_profile_status(profile.profile_status)
    |> validate_entity_type(profile.entity_type)
    |> validate_business_owner_email(profile.business_owner_email)
  end

  defp validate_business_owner_email(errors, nil), do: errors

  defp validate_business_owner_email(errors, email) when is_binary(email) do
    if String.length(email) > 254 do
      ["Business owner email must be 254 characters or less" | errors]
    else
      errors
    end
  end

  defp validate_business_owner_email(errors, _), do: ["Business owner email must be a string" | errors]

  defp validate_identity_id(errors, identity_id) when is_binary(identity_id) do
    if String.trim(identity_id) == "" do
      ["Identity ID cannot be empty" | errors]
    else
      errors
    end
  end

  defp validate_identity_id(errors, _), do: ["Identity ID must be a string" | errors]

  defp validate_business_name(errors, business_name) when is_binary(business_name) do
    trimmed = String.trim(business_name)

    cond do
      trimmed == "" -> ["Business name cannot be empty" | errors]
      String.length(trimmed) > 200 -> ["Business name must be 200 characters or less" | errors]
      true -> errors
    end
  end

  defp validate_business_name(errors, _), do: ["Business name must be a string" | errors]

  defp validate_description(errors, nil), do: errors

  defp validate_description(errors, description) when is_binary(description) do
    trimmed = String.trim(description)

    cond do
      trimmed == "" -> ["Description cannot be empty if provided" | errors]
      String.length(trimmed) > 1000 -> ["Description must be 1000 characters or less" | errors]
      true -> errors
    end
  end

  defp validate_description(errors, _), do: ["Description must be a string" | errors]

  defp validate_phone(errors, nil), do: errors

  defp validate_phone(errors, phone) when is_binary(phone) do
    trimmed = String.trim(phone)

    cond do
      trimmed == "" -> ["Phone cannot be empty if provided" | errors]
      String.length(trimmed) > 20 -> ["Phone must be 20 characters or less" | errors]
      true -> errors
    end
  end

  defp validate_phone(errors, _), do: ["Phone must be a string" | errors]

  defp validate_website(errors, nil), do: errors

  defp validate_website(errors, website) when is_binary(website) do
    trimmed = String.trim(website)

    cond do
      trimmed == "" ->
        ["Website cannot be empty if provided" | errors]

      not String.starts_with?(trimmed, "https://") ->
        ["Website must start with https://" | errors]

      String.length(trimmed) > 500 ->
        ["Website must be 500 characters or less" | errors]

      true ->
        errors
    end
  end

  defp validate_website(errors, _), do: ["Website must be a string" | errors]

  defp validate_address(errors, nil), do: errors

  defp validate_address(errors, address) when is_binary(address) do
    trimmed = String.trim(address)

    cond do
      trimmed == "" -> ["Address cannot be empty if provided" | errors]
      String.length(trimmed) > 500 -> ["Address must be 500 characters or less" | errors]
      true -> errors
    end
  end

  defp validate_address(errors, _), do: ["Address must be a string" | errors]

  defp validate_logo_url(errors, nil), do: errors

  defp validate_logo_url(errors, logo_url) when is_binary(logo_url) do
    trimmed = String.trim(logo_url)

    cond do
      trimmed == "" -> ["Logo URL cannot be empty if provided" | errors]
      String.length(trimmed) > 500 -> ["Logo URL must be 500 characters or less" | errors]
      true -> errors
    end
  end

  defp validate_logo_url(errors, _), do: ["Logo URL must be a string" | errors]

  defp validate_verified(errors, nil), do: errors
  defp validate_verified(errors, verified) when is_boolean(verified), do: errors
  defp validate_verified(errors, _), do: ["Verified must be a boolean" | errors]

  defp validate_verified_at(errors, nil), do: errors
  defp validate_verified_at(errors, %DateTime{}), do: errors
  defp validate_verified_at(errors, _), do: ["Verified at must be a DateTime" | errors]

  defp validate_categories(errors, nil), do: errors

  defp validate_categories(errors, categories) when is_list(categories) do
    if Enum.all?(categories, &is_binary/1) do
      errors
    else
      ["Categories must be a list of strings" | errors]
    end
  end

  defp validate_categories(errors, _), do: ["Categories must be a list" | errors]

  defp validate_profile_status(errors, status) when status in @profile_statuses, do: errors
  defp validate_profile_status(errors, _), do: ["profile_status must be :draft or :active" | errors]

  defp validate_entity_type(errors, entity_type) when entity_type in @entity_types, do: errors
  defp validate_entity_type(errors, _), do: ["entity_type must be :individual or :business" | errors]
end
