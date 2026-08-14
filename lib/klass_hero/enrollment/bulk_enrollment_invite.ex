defmodule KlassHero.Enrollment.BulkEnrollmentInvite do
  @moduledoc """
  A denormalized CSV-import staging record (`bulk_enrollment_invites` table).

  When a guardian acts on the invite, real domain entities (User, ParentProfile,
  Child, Enrollment, Consents) are created from this data.

  This module is both the Ecto schema and the struct consumers pattern-match.
  The changesets are the validation gatekeepers; the predicates, `generate_token/0`,
  `dedup_key/4` and `describe_failure/2` are the functional core. Status follows a
  state machine (see `valid_transitions/0`).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.Enrollment.Domain.Services.InviteFieldValidations
  alias KlassHero.Shared.ChangesetErrors

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  @statuses [:pending, :invite_sent, :registered, :enrolled, :failed]
  @resendable_statuses [:pending, :invite_sent, :failed]

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

    # When the provider last reopened this invite. Compared against an Oban job's
    # `inserted_at` to tell a compensation whether the job it speaks for still describes
    # this invite — `failed: [:pending]` means a resend can undo a compensation, so a
    # dead job must not silently redo it (#1339). `nil` means never resent.
    field :resent_at, :utc_datetime_usec

    timestamps()
  end

  @type t :: %__MODULE__{}

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

  @lifecycle_fields ~w(status invite_token invite_sent_at registered_at enrolled_at enrollment_id error_details resent_at)a

  def valid_transitions, do: @valid_transitions

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

  @doc """
  Changeset for creating invite records from CSV import data.

  Only accepts fields from the CSV. Status defaults to `:pending`.
  Lifecycle fields are managed via `transition_changeset/2`.
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
  Changeset for transitioning invite status, validating the transition is
  legal per the state machine.
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

  @doc "Returns true if the invite is in `:pending` status."
  @spec pending?(t()) :: boolean()
  def pending?(%__MODULE__{status: :pending}), do: true
  def pending?(%__MODULE__{}), do: false

  @doc "Returns true if the invite is in `:invite_sent` status."
  @spec invite_sent?(t()) :: boolean()
  def invite_sent?(%__MODULE__{status: :invite_sent}), do: true
  def invite_sent?(%__MODULE__{}), do: false

  @doc "Returns true if the invite status allows resending."
  @spec resendable?(t()) :: boolean()
  def resendable?(%__MODULE__{status: status}) when status in @resendable_statuses, do: true
  def resendable?(%__MODULE__{}), do: false

  @doc """
  Tuple-returning variant of `resendable?/1` for composing in `with` chains.
  """
  @spec ensure_resendable(t()) :: {:ok, t()} | {:error, :not_resendable}
  def ensure_resendable(%__MODULE__{status: status} = invite) when status in @resendable_statuses, do: {:ok, invite}
  def ensure_resendable(%__MODULE__{}), do: {:error, :not_resendable}

  @doc """
  Tuple-returning input guard for the claim path — an invite may only be claimed
  from `:invite_sent` status.
  """
  @spec ensure_claimable(t()) :: {:ok, t()} | {:error, :already_claimed}
  def ensure_claimable(%__MODULE__{status: :invite_sent} = invite), do: {:ok, invite}
  def ensure_claimable(%__MODULE__{}), do: {:error, :already_claimed}

  @doc """
  The sentence a provider reads under a failed invite's status pill.

  `error_details` is rendered verbatim to providers so the reason is *actionable*
  (#1221), which means no clause here may emit `inspect/1` output — see #1290, where
  three of the four writers had each invented their own convention and two emitted raw
  Elixir terms. Diagnostics belong in the `Logger` calls the writers already make.

  Takes the invite as well as the reason because a missing token is a fact about the
  row that no reason can carry: the compensation sweep hands back `nil` for a Lifeline
  discard, and Oban's own error text otherwise, so by then the original term is gone.
  """
  @spec describe_failure(t(), term()) :: String.t()
  # First, because the row outranks the reason: a tokenless invite failed for want of a
  # token whatever the caller believed went wrong, and the resend that mints a new one
  # is different advice from retrying a delivery.
  def describe_failure(%__MODULE__{invite_token: nil}, _reason) do
    "Invite link could not be generated (no token). Please resend."
  end

  def describe_failure(%__MODULE__{}, %Ecto.Changeset{} = changeset) do
    case ChangesetErrors.field_list(changeset) do
      # A changeset can be invalid with its errors on an association rather than a field.
      # Falling back to the generic sentence loses detail; falling back to `inspect/1`
      # would lose the provider.
      [] -> generic_failure()
      fields -> Enum.map_join(fields, "; ", fn {field, message} -> "#{humanize_field(field)} #{message}" end)
    end
  end

  def describe_failure(%__MODULE__{}, :program_full) do
    "The program is full, so this child could not be enrolled."
  end

  def describe_failure(%__MODULE__{}, {:invalid_date, value}) when is_binary(value) do
    ~s(Date of birth "#{value}" is not a valid date. Please correct it and resend.)
  end

  def describe_failure(%__MODULE__{}, {:delivery, _reason}) do
    "The invitation email could not be delivered. Please check the address and resend."
  end

  # `nil` is a Lifeline discard, which records no cause at all; a binary is Oban's own
  # error text — `Exception.format/3` output or "... failed with #{inspect(reason)}" —
  # which is developer copy by construction. Both give the provider the fact without a
  # cause rather than a term they cannot act on.
  def describe_failure(%__MODULE__{}, reason) when is_nil(reason) or is_binary(reason) do
    "This invite could not be completed and no retries remain. Please resend."
  end

  def describe_failure(%__MODULE__{}, _other), do: generic_failure()

  defp generic_failure, do: "This invite could not be completed. Please resend."

  defp humanize_field(field) do
    field
    |> Atom.to_string()
    |> String.replace("_", " ")
  end

  @doc "Generates a cryptographically secure URL-safe token for invite links."
  @spec generate_token() :: String.t()
  def generate_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  @doc """
  Natural dedup key for an invite — program_id plus downcased guardian email
  and child name, matching the case-insensitive DB unique index.
  """
  @spec dedup_key(binary(), String.t(), String.t(), String.t()) ::
          {binary(), String.t(), String.t(), String.t()}
  def dedup_key(program_id, guardian_email, child_first_name, child_last_name)
      when is_binary(program_id) and is_binary(guardian_email) and is_binary(child_first_name) and
             is_binary(child_last_name) do
    {program_id, String.downcase(guardian_email), String.downcase(child_first_name), String.downcase(child_last_name)}
  end
end
