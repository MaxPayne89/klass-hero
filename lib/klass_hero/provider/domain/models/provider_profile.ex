defmodule KlassHero.Provider.Domain.Models.ProviderProfile do
  @moduledoc """
  Pure domain entity representing a provider profile in the Provider bounded context.

  This is the aggregate root for provider-related operations in the Provider context.
  Contains only business logic and validation rules, no database dependencies.

  Providers are linked to the Accounts context via correlation ID (identity_id),
  not foreign key, maintaining bounded context independence.
  """

  @enforce_keys [:id, :identity_id, :business_name]

  defstruct [
    :id,
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
    :profile_status,
    :entity_type,
    :inserted_at,
    :updated_at
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          identity_id: String.t(),
          business_name: String.t(),
          business_owner_email: String.t() | nil,
          description: String.t() | nil,
          phone: String.t() | nil,
          website: String.t() | nil,
          address: String.t() | nil,
          logo_url: String.t() | nil,
          verified: boolean() | nil,
          verified_at: DateTime.t() | nil,
          verified_by_id: String.t() | nil,
          categories: [String.t()] | nil,
          profile_status: :draft | :active | nil,
          entity_type: :individual | :business | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc """
  Creates a new ProviderProfile with validation.

  Business Rules:
  - identity_id must be present and non-empty (UUID string)
  - business_name must be present, non-empty, and <= 200 characters
  - description if present, must be non-empty and <= 1000 characters
  - phone if present, must be non-empty and <= 20 characters
  - website if present, must start with https:// and <= 500 characters
  - address if present, must be non-empty and <= 500 characters
  - logo_url if present, must be non-empty and <= 500 characters
  - verified if present, must be a boolean (defaults to false)
  - verified_at if present, must be a DateTime (independent of verified)
  - categories if present, must be a list of strings (defaults to [])

  Returns:
  - `{:ok, provider_profile}` if all validations pass
  - `{:error, [reasons]}` with list of validation errors
  """
  def new(attrs) do
    attrs_with_defaults = apply_defaults(attrs)
    provider_profile = struct!(__MODULE__, attrs_with_defaults)

    case validate(provider_profile) do
      [] -> {:ok, provider_profile}
      errors -> {:error, errors}
    end
  end

  defp apply_defaults(attrs) do
    attrs
    |> Map.put_new(:verified, false)
    |> Map.put_new(:categories, [])
    |> Map.put_new(:profile_status, :active)
    |> Map.put_new(:entity_type, :individual)
  end

  @doc """
  Validates that a provider profile struct has valid business rules.
  """
  def valid?(%__MODULE__{} = provider_profile) do
    validate(provider_profile) == []
  end

  @doc """
  Checks if the provider has been verified.
  """
  def verified?(%__MODULE__{verified: true}), do: true
  def verified?(_), do: false

  @doc """
  Marks a provider profile as verified.

  Records the admin who performed the verification and the timestamp. A `nil` admin denotes a
  **system verification** — the Vetting engine crossing to `:verified` with no human reviewer
  (e.g. when a Stripe Identity outcome is the final required step); `verified_by_id` is left nil.
  Idempotent - verifying an already-verified provider updates the audit trail.
  """
  def verify(%__MODULE__{} = profile, admin_id) when is_binary(admin_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, %{profile | verified: true, verified_at: now, verified_by_id: admin_id, updated_at: now}}
  end

  def verify(%__MODULE__{} = profile, nil) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, %{profile | verified: true, verified_at: now, verified_by_id: nil, updated_at: now}}
  end

  @doc """
  Revokes verification from a provider profile.

  Clears the verified flag, timestamp, and admin audit trail.
  Idempotent - unverifying an already-unverified provider succeeds.
  """
  def unverify(%__MODULE__{} = profile) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    {:ok, %{profile | verified: false, verified_at: nil, verified_by_id: nil, updated_at: now}}
  end

  defp validate(%__MODULE__{} = provider_profile) do
    []
    |> validate_identity_id(provider_profile.identity_id)
    |> validate_business_name(provider_profile.business_name)
    |> validate_description(provider_profile.description)
    |> validate_phone(provider_profile.phone)
    |> validate_website(provider_profile.website)
    |> validate_address(provider_profile.address)
    |> validate_logo_url(provider_profile.logo_url)
    |> validate_verified(provider_profile.verified)
    |> validate_verified_at(provider_profile.verified_at)
    |> validate_categories(provider_profile.categories)
    |> validate_profile_status(provider_profile.profile_status)
    |> validate_entity_type(provider_profile.entity_type)
    |> validate_business_owner_email(provider_profile.business_owner_email)
  end

  @valid_entity_types [:individual, :business]

  defp validate_entity_type(errors, entity_type) when entity_type in @valid_entity_types, do: errors

  defp validate_entity_type(errors, _), do: ["entity_type must be :individual or :business" | errors]

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
    trimmed = String.trim(identity_id)

    if trimmed == "" do
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

  @valid_profile_statuses [:draft, :active]

  defp validate_profile_status(errors, status) when status in @valid_profile_statuses, do: errors

  defp validate_profile_status(errors, _), do: ["profile_status must be :draft or :active" | errors]

  @doc """
  Returns true if the profile is in draft status (needs completion).
  """
  def draft?(%__MODULE__{profile_status: :draft}), do: true
  def draft?(_), do: false

  @doc """
  Completes a draft provider profile with the given fields.

  Only allowed when profile_status is :draft. Sets status to :active.
  Accepts: business_name, description, phone, website, address, logo_url, categories.

  Returns:
  - `{:ok, updated_profile}` on success
  - `{:error, :already_active}` if profile_status is not :draft
  - `{:error, errors}` if validation fails
  """
  @completion_fields ~w(business_name description phone website address logo_url categories)a

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
end
