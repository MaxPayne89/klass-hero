defmodule KlassHero.Family.Domain.Models.Consent do
  @moduledoc """
  Consent domain entity representing parental consent in the Family bounded context.

  This is a pure domain model with no persistence or infrastructure concerns.
  Validation happens at the domain boundary.

  Multiple consent records per (child, consent_type) are allowed for audit history.
  Active consent is determined by `withdrawn_at` being nil.

  ## Fields

  - `id` - Unique identifier for the consent record
  - `parent_id` - Reference to the parent who granted consent
  - `child_id` - Reference to the child the consent applies to
  - `consent_type` - Type of consent (e.g. "photo_marketing", "photo_social_media", "medical", "participation", "provider_data_sharing")
  - `granted_at` - When consent was granted
  - `withdrawn_at` - When consent was withdrawn (nil if still active)
  - `inserted_at` - When the record was created
  - `updated_at` - When the record was last updated
  """

  use KlassHero.Shared.Domain.Models.PersistenceSupport

  @valid_consent_types ~w(provider_data_sharing photo_marketing photo_social_media medical participation)

  @doc """
  Returns the list of valid consent types.
  """
  def valid_consent_types, do: @valid_consent_types

  @enforce_keys [:id, :parent_id, :child_id, :consent_type, :granted_at]
  defstruct [
    :id,
    :parent_id,
    :child_id,
    :consent_type,
    :granted_at,
    :withdrawn_at,
    :inserted_at,
    :updated_at
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          parent_id: String.t(),
          child_id: String.t(),
          consent_type: String.t(),
          granted_at: DateTime.t(),
          withdrawn_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc """
  Creates a new Consent with validation.

  Business Rules:
  - parent_id must be present and non-empty
  - child_id must be present and non-empty
  - consent_type must be present and non-empty
  - granted_at must be a DateTime

  Returns:
  - `{:ok, consent}` if all validations pass
  - `{:error, [reasons]}` with list of validation errors
  """
  def new(attrs) do
    consent = struct!(__MODULE__, attrs)

    case validate(consent) do
      [] -> {:ok, consent}
      errors -> {:error, errors}
    end
  end

  @doc """
  Validates that a consent struct has valid business rules.
  """
  def valid?(%__MODULE__{} = consent) do
    validate(consent) == []
  end

  @doc """
  Returns true when consent is still active (not withdrawn).
  """
  def active?(%__MODULE__{withdrawn_at: nil}), do: true
  def active?(%__MODULE__{}), do: false

  @doc """
  Withdraws an active consent by setting `withdrawn_at` to the current time.

  Returns:
  - `{:ok, consent}` with `withdrawn_at` set
  - `{:error, :already_withdrawn}` if consent was already withdrawn
  """
  def withdraw(%__MODULE__{withdrawn_at: nil} = consent) do
    {:ok, %{consent | withdrawn_at: DateTime.utc_now() |> DateTime.truncate(:second)}}
  end

  def withdraw(%__MODULE__{}) do
    {:error, :already_withdrawn}
  end

  defp validate(%__MODULE__{} = consent) do
    []
    |> validate_parent_id(consent.parent_id)
    |> validate_child_id(consent.child_id)
    |> validate_consent_type(consent.consent_type)
    |> validate_granted_at(consent.granted_at)
  end

  defp validate_parent_id(errors, parent_id) when is_binary(parent_id) do
    if String.trim(parent_id) == "" do
      ["Parent ID cannot be empty" | errors]
    else
      errors
    end
  end

  defp validate_parent_id(errors, _), do: ["Parent ID must be a string" | errors]

  defp validate_child_id(errors, child_id) when is_binary(child_id) do
    if String.trim(child_id) == "" do
      ["Child ID cannot be empty" | errors]
    else
      errors
    end
  end

  defp validate_child_id(errors, _), do: ["Child ID must be a string" | errors]

  defp validate_consent_type(errors, consent_type) when is_binary(consent_type) do
    trimmed = String.trim(consent_type)

    cond do
      trimmed == "" ->
        ["Consent type cannot be empty" | errors]

      trimmed not in @valid_consent_types ->
        ["Consent type must be one of: #{Enum.join(@valid_consent_types, ", ")}" | errors]

      true ->
        errors
    end
  end

  defp validate_consent_type(errors, _), do: ["Consent type must be a string" | errors]

  defp validate_granted_at(errors, %DateTime{}), do: errors
  defp validate_granted_at(errors, _), do: ["Granted at must be a DateTime" | errors]
end
