defmodule KlassHero.Accounts.User do
  @moduledoc """
  User schema and changesets for authentication.

  Defines the user data structure with email-based authentication,
  password hashing with Bcrypt, and email confirmation tracking.
  Provides changesets for registration, email changes, and password management.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.Accounts.Domain.Models.User, as: DomainUser
  alias KlassHero.Accounts.Types.{UserRole, UserRoles}
  # Cross-context references for admin dashboard preloading (read-only).
  # Pragmatic DDD boundary crossing — see AccountLive moduledoc.
  alias KlassHero.Accounts.User
  alias KlassHero.Family.Adapters.Driven.Persistence.Schemas.ParentProfileSchema
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.ProviderProfileSchema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :email, :string
    field :name, :string
    field :avatar, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime
    field :authenticated_at, :utc_datetime, virtual: true
    field :intended_roles, UserRoles, default: []
    field :locale, :string, default: "en"
    field :is_admin, :boolean, default: false

    has_one :parent_profile, ParentProfileSchema, foreign_key: :identity_id
    has_one :provider_profile, ProviderProfileSchema, foreign_key: :identity_id

    timestamps(type: :utc_datetime)
  end

  # GDPR: Prevent personal data from leaking in logs/exceptions
  defimpl Inspect, for: __MODULE__ do
    @sensitive_fields [:email, :name, :password, :hashed_password]

    def inspect(user, _opts) do
      pruned =
        user
        |> Map.from_struct()
        |> Map.drop(@sensitive_fields)
        |> Map.delete(:__meta__)

      "#KlassHero.Accounts.User<#{inspect(pruned)}>"
    end
  end

  @doc """
  A user changeset for registration.

  Validates name, email, and intended_roles fields, sets a default role.

  ## Options

    * `:validate_unique` - Set to false if you don't want to validate the
      uniqueness of the email. Defaults to `true`.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:name, :email, :intended_roles])
    |> put_default_role()
    |> validate_required([:name, :email, :intended_roles])
    |> validate_length(:name, min: 2, max: 100)
    |> validate_subset(:intended_roles, UserRole.valid_roles())
    |> validate_at_least_one_role()
    |> validate_email(opts)
  end

  @doc """
  A user changeset for staff registration via an invitation link.

  Sets `intended_roles` to `[:staff]` only. Per ADR-0005, being hired as
  staff is NOT becoming a provider — provider-hood is a deliberate, separate
  act (self-registration or an explicit staff→provider upgrade). Accepting an
  invite therefore never grants `:provider` and never creates a ProviderProfile.

  ## Options

    * `:validate_unique` - Set to false if you don't want to validate the
      uniqueness of the email. Defaults to `true`.
  """
  def staff_registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:name, :email])
    |> validate_required([:name, :email])
    |> validate_length(:name, min: 2, max: 100)
    |> put_change(:intended_roles, [:staff])
    |> validate_email(opts)
    |> password_changeset(attrs, opts)
  end

  defp put_default_role(changeset) do
    case get_field(changeset, :intended_roles) do
      nil -> put_change(changeset, :intended_roles, [:parent])
      [] -> put_change(changeset, :intended_roles, [:parent])
      _ -> changeset
    end
  end

  @doc """
  A user changeset for registering or changing the email.

  It requires the email to change otherwise an error is added.

  ## Options

    * `:validate_unique` - Set to false if you don't want to validate the
      uniqueness of the email, useful when displaying live validations.
      Defaults to `true`.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:email])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/, message: "must have the @ sign and no spaces")
      |> validate_length(:email, max: 160)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, KlassHero.Repo)
      |> unique_constraint(:email)
      |> validate_email_changed()
    else
      changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "did not change")
    else
      changeset
    end
  end

  defp validate_at_least_one_role(changeset) do
    roles = get_field(changeset, :intended_roles) || []

    if Enum.empty?(roles) do
      add_error(changeset, :intended_roles, "must select at least one role")
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing the password.

  It is important to validate the length of the password, as long passwords may
  be very expensive to hash for certain algorithms.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      |> validate_length(:password, max: 72, count: :bytes)
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = DateTime.utc_now(:second)
    change(user, confirmed_at: now)
  end

  @doc """
  Anonymizes the user account for GDPR deletion requests.

  Replaces PII fields with anonymized values:
  - Email: `deleted_<user_id>@anonymized.local`
  - Name: `"Deleted User"` (placeholder)
  - Avatar: `nil` (cleared)

  Timestamps and other non-PII data are preserved for data integrity.
  """
  def anonymize_changeset(%__MODULE__{id: id} = user) do
    # Trigger: domain model owns the definition of "anonymized"
    # Why: single source of truth for GDPR anonymization values
    # Outcome: schema changeset delegates field values to the domain model
    attrs = DomainUser.anonymized_attrs()
    anonymized_email = attrs.email_fn.(id)

    change(user, email: anonymized_email, name: attrs.name, avatar: attrs.avatar)
  end

  @supported_locales ~w(en de)

  @doc """
  A user changeset for changing locale preference.

  Validates that the locale is one of the supported locales: #{inspect(@supported_locales)}.
  """
  def locale_changeset(user, attrs) do
    user
    |> cast(attrs, [:locale])
    |> validate_required([:locale])
    |> validate_inclusion(:locale, @supported_locales)
  end

  @doc """
  A changeset for admin edits to user accounts.

  Only allows toggling admin status. All other fields
  (email, name, password, intended_roles) are excluded from the cast whitelist.

  Accepts 3 args to match the Backpex changeset callback signature.
  """
  def admin_update_changeset(user, attrs, _metadata) do
    cast(user, attrs, [:is_admin])
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end
end
