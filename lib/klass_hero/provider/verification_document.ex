defmodule KlassHero.Provider.VerificationDocument do
  @moduledoc """
  Provider verification document (`verification_documents` table).

  Owned by the Provider context. A provider submits a document for admin review;
  it moves through a simple lifecycle: `:pending` -> `:approved` | `:rejected`.

  This module is both the Ecto schema and the struct consumers pattern-match.
  The changeset is the single validation gatekeeper; the pure transition
  functions (`approve/2`, `reject/3`) are the functional core enforcing the
  pending-only guard.

  ## Field naming

  The struct field is `provider_profile_id` (semantic clarity) but the underlying
  DB column is `provider_id`, which references the `providers` table. The
  `belongs_to :provider` association carries the `source: :provider_id` mapping so
  consumers keep reading `document.provider_profile_id`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.Accounts.User
  # Parked alias to the still-DDD ProviderProfile schema — repointed to the
  # flattened KlassHero.Provider.ProviderProfile in Slice 5.
  alias KlassHero.Provider.ProviderProfile
  alias KlassHero.Provider.Types.DocumentType
  alias KlassHero.Provider.Vetting

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @statuses [:pending, :approved, :rejected]
  # An expiry within this many days of today is "expiring soon" (vetting step B3, #957).
  @warning_window_days 30
  # Canonical write-side values are owned by the custom `DocumentType` type, which
  # also tolerates unknown legacy values on load (maps them to `:unknown`, #1026).
  @document_types DocumentType.valid_values()

  schema "verification_documents" do
    field :document_type, DocumentType
    field :file_url, :string
    field :original_filename, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :rejection_reason, :string
    field :reviewed_at, :utc_datetime_usec
    # Nullable policy expiry — only documents that expire (insurance, safeguarding) populate it.
    field :expiry_date, :date

    belongs_to :provider, ProviderProfile,
      foreign_key: :provider_profile_id,
      source: :provider_id,
      references: :id

    belongs_to :reviewed_by, User

    timestamps()
  end

  @type t :: %__MODULE__{}
  @type status :: :pending | :approved | :rejected

  @typedoc """
  Pairs a document with its provider's display name plus the structured business-registration
  facts (legal name + registration number, nil for non-business docs) for admin review screens.
  """
  @type admin_review_result :: %{
          document: t(),
          provider_business_name: String.t(),
          legal_business_name: String.t() | nil,
          registration_number: String.t() | nil
        }

  @required_fields ~w(provider_profile_id document_type file_url original_filename)a
  @optional_fields ~w(id status rejection_reason reviewed_by_id reviewed_at expiry_date)a

  @doc "Returns the list of valid document statuses."
  @spec valid_statuses() :: [status()]
  def valid_statuses, do: @statuses

  @doc "Returns the list of valid document types."
  @spec valid_document_types() :: [atom()]
  def valid_document_types, do: @document_types

  @doc """
  Returns the document-type strings consumed by the given vetting track's document
  steps, in track order. Single-sources the per-track whitelist from the engine
  catalog so a new document step is picked up automatically.
  """
  @spec valid_document_types(:individual | :business) :: [String.t()]
  def valid_document_types(entity_type) do
    entity_type
    |> Vetting.track()
    |> Enum.flat_map(fn
      %{completed_via: {:document, type}} -> [type]
      _ -> []
    end)
  end

  @doc """
  Whether the given document type must carry an `expiry_date` at submission.

  Insurance certificates expire and drive the expiry warning (B3, #957); every other
  type is one-time evidence with no expiry. Consulted by the submit command so the
  required-ness lives here in the domain, not hardcoded in the shared changeset.
  """
  @spec expiry_required?(String.t()) :: boolean()
  def expiry_required?("insurance_certificate"), do: true
  def expiry_required?(_type), do: false

  @doc """
  Classifies a policy expiry date relative to `today` for the expiry warning (B3, #957):

  - `:none` — no expiry date recorded
  - `:expired` — the certificate has lapsed
  - `:expiring_soon` — within #{@warning_window_days} days of lapsing
  - `:valid` — comfortably in date

  Accepts a bare `Date`, a `%VerificationDocument{}` (reads its `expiry_date`), or `nil`,
  so the provider widget, admin review, and the future scheduled scan share one classifier.
  """
  @spec expiry_status(Date.t() | t() | nil, Date.t()) :: :none | :expired | :expiring_soon | :valid
  def expiry_status(%__MODULE__{expiry_date: date}, today), do: expiry_status(date, today)
  def expiry_status(nil, _today), do: :none

  def expiry_status(%Date{} = date, %Date{} = today) do
    cond do
      Date.before?(date, today) -> :expired
      Date.diff(date, today) <= @warning_window_days -> :expiring_soon
      true -> :valid
    end
  end

  @doc """
  Changeset for inserting a verification document.

  The single validation gatekeeper for creation. `Ecto.Enum` already rejects
  invalid `status`/`document_type` values on cast, so no `validate_inclusion` is
  needed here — decide what invariants still belong at this boundary.
  """
  def create_changeset(schema \\ %__MODULE__{}, attrs) do
    schema
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:provider_profile_id, name: :verification_documents_provider_id_fkey)
    |> foreign_key_constraint(:reviewed_by_id)
  end

  @doc """
  Changeset for persisting an admin review decision (approve/reject).

  Casts only the reviewer-controlled fields; the pending-only guard lives in the
  `approve/2` and `reject/3` transition functions, not here.
  """
  def review_changeset(%__MODULE__{} = doc, attrs) do
    doc
    |> cast(attrs, ~w(status rejection_reason reviewed_by_id reviewed_at)a)
    |> validate_required(~w(status reviewed_by_id reviewed_at)a)
    |> foreign_key_constraint(:reviewed_by_id)
  end

  @doc """
  Approves a pending document, recording the reviewer.

  Returns `{:ok, t()}` with the transitioned struct, `{:error, :invalid_reviewer}`
  for a blank reviewer id, or `{:error, :document_not_pending}` when not pending.
  """
  @spec approve(t(), String.t()) ::
          {:ok, t()} | {:error, :invalid_reviewer | :document_not_pending}
  def approve(%__MODULE__{status: :pending} = doc, reviewer_id)
      when is_binary(reviewer_id) and byte_size(reviewer_id) > 0 do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, %{doc | status: :approved, reviewed_by_id: reviewer_id, reviewed_at: now}}
  end

  def approve(%__MODULE__{status: :pending}, _reviewer_id), do: {:error, :invalid_reviewer}
  def approve(%__MODULE__{}, _reviewer_id), do: {:error, :document_not_pending}

  @doc """
  Rejects a pending document with a reason, recording the reviewer.

  Returns `{:ok, t()}`, `{:error, :invalid_review_params}` for a blank reviewer id
  or reason, or `{:error, :document_not_pending}` when not pending.
  """
  @spec reject(t(), String.t(), String.t()) ::
          {:ok, t()} | {:error, :invalid_review_params | :document_not_pending}
  def reject(%__MODULE__{status: :pending} = doc, reviewer_id, reason)
      when is_binary(reviewer_id) and byte_size(reviewer_id) > 0 and is_binary(reason) and byte_size(reason) > 0 do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok,
     %{
       doc
       | status: :rejected,
         rejection_reason: reason,
         reviewed_by_id: reviewer_id,
         reviewed_at: now
     }}
  end

  def reject(%__MODULE__{status: :pending}, _reviewer_id, _reason), do: {:error, :invalid_review_params}

  def reject(%__MODULE__{}, _reviewer_id, _reason), do: {:error, :document_not_pending}
end
