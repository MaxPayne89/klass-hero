defmodule KlassHero.Enrollment.Domain.Models.BulkEnrollmentInvite do
  @moduledoc """
  Domain entity for a bulk enrollment invite in the Enrollment bounded context.

  Represents a denormalized staging record created from CSV import. When a
  guardian acts on the invite, real domain entities (User, ParentProfile,
  Child, Enrollment, Consents) are created from this data.

  This is a pure domain model with no persistence concerns.
  """

  use KlassHero.Shared.Domain.Models.PersistenceSupport

  @enforce_keys [
    :id,
    :program_id,
    :provider_id,
    :status,
    :guardian_email,
    :child_first_name,
    :child_last_name
  ]

  defstruct [
    :id,
    :program_id,
    :provider_id,
    :child_first_name,
    :child_last_name,
    :child_date_of_birth,
    :guardian_email,
    :guardian_first_name,
    :guardian_last_name,
    :guardian2_email,
    :guardian2_first_name,
    :guardian2_last_name,
    :school_grade,
    :school_name,
    :medical_conditions,
    :nut_allergy,
    :consent_photo_marketing,
    :consent_photo_social_media,
    :status,
    :invite_token,
    :invite_sent_at,
    :registered_at,
    :enrolled_at,
    :enrollment_id,
    :error_details
  ]

  @type status :: :pending | :invite_sent | :registered | :enrolled | :failed

  @type t :: %__MODULE__{
          id: String.t(),
          program_id: String.t(),
          provider_id: String.t(),
          child_first_name: String.t(),
          child_last_name: String.t(),
          child_date_of_birth: Date.t() | nil,
          guardian_email: String.t(),
          guardian_first_name: String.t() | nil,
          guardian_last_name: String.t() | nil,
          guardian2_email: String.t() | nil,
          guardian2_first_name: String.t() | nil,
          guardian2_last_name: String.t() | nil,
          school_grade: non_neg_integer() | nil,
          school_name: String.t() | nil,
          medical_conditions: String.t() | nil,
          nut_allergy: boolean() | nil,
          consent_photo_marketing: boolean() | nil,
          consent_photo_social_media: boolean() | nil,
          status: status(),
          invite_token: String.t() | nil,
          invite_sent_at: DateTime.t() | nil,
          registered_at: DateTime.t() | nil,
          enrolled_at: DateTime.t() | nil,
          enrollment_id: String.t() | nil,
          error_details: String.t() | nil
        }

  @doc "Returns true if the invite is in `:pending` status."
  @spec pending?(t()) :: boolean()
  def pending?(%__MODULE__{status: :pending}), do: true
  def pending?(%__MODULE__{}), do: false

  @doc "Returns true if the invite is in `:invite_sent` status."
  @spec invite_sent?(t()) :: boolean()
  def invite_sent?(%__MODULE__{status: :invite_sent}), do: true
  def invite_sent?(%__MODULE__{}), do: false

  @resendable_statuses [:pending, :invite_sent, :failed]

  @doc "Returns true if the invite status allows resending."
  @spec resendable?(t()) :: boolean()
  def resendable?(%__MODULE__{status: status}) when status in @resendable_statuses, do: true
  def resendable?(%__MODULE__{}), do: false

  @doc """
  Tuple-returning variant of `resendable?/1` for composing in `with` chains.

  Returns `{:ok, invite}` when the status allows resending,
  `{:error, :not_resendable}` otherwise.
  """
  @spec ensure_resendable(t()) :: {:ok, t()} | {:error, :not_resendable}
  def ensure_resendable(%__MODULE__{status: status} = invite) when status in @resendable_statuses, do: {:ok, invite}

  def ensure_resendable(%__MODULE__{}), do: {:error, :not_resendable}

  @doc """
  Tuple-returning input guard for the claim path.

  Returns `{:ok, invite}` when the invite is in `:invite_sent` status (the
  only state from which a token may be claimed), `{:error, :already_claimed}`
  otherwise. Designed to compose in a `with` chain at the use-case boundary.
  """
  @spec ensure_claimable(t()) :: {:ok, t()} | {:error, :already_claimed}
  def ensure_claimable(%__MODULE__{status: :invite_sent} = invite), do: {:ok, invite}
  def ensure_claimable(%__MODULE__{}), do: {:error, :already_claimed}

  @doc "Generates a cryptographically secure URL-safe token for invite links."
  @spec generate_token() :: String.t()
  def generate_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  @doc """
  Natural dedup key for an invite — program_id plus downcased guardian
  email and child name. The DB unique index is case-insensitive via
  downcased tuple matching, and both write paths use this shape so the
  key in application code always equals the key materialised from the DB.
  """
  @spec dedup_key(binary(), String.t(), String.t(), String.t()) ::
          {binary(), String.t(), String.t(), String.t()}
  def dedup_key(program_id, guardian_email, child_first_name, child_last_name)
      when is_binary(program_id) and is_binary(guardian_email) and is_binary(child_first_name) and
             is_binary(child_last_name) do
    {
      program_id,
      String.downcase(guardian_email),
      String.downcase(child_first_name),
      String.downcase(child_last_name)
    }
  end
end
