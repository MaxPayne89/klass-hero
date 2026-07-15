defmodule KlassHero.Provider.SignedAgreement do
  @moduledoc """
  Evidence for an auto-approving agreement vetting step: a provider's explicit, recorded consent
  to a versioned agreement. Today this is the individual track's Community Standards Agreement
  (Step 6); the business track's staff attestation reuses the same model via `kind`.

  Schema-as-struct: simultaneously the Ecto schema for `signed_agreements`, the struct consumers
  match on, and the functional core. Append-only — a re-agreement (e.g. after a guidelines version
  bump) is a fresh record, never an update, so the consent history stays auditable. The step it
  backs auto-approves on submission; there is no admin review, hence no approve/reject here.

  Stores who agreed (`signed_by_name`), when (`signed_at`), and to which `version` of the
  guidelines, so a material update can require re-agreement against the new version. It never
  stores the agreement text — that is versioned presentation (see `CommunityGuidelines`).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.Provider.ProviderProfile

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @kinds [:community_agreement, :staff_attestation]
  @entity_types [:individual, :business]

  schema "signed_agreements" do
    field :kind, Ecto.Enum, values: @kinds, default: :community_agreement
    field :entity_type, Ecto.Enum, values: @entity_types
    field :signed_by_name, :string
    field :signed_at, :utc_datetime_usec
    field :version, :string

    belongs_to :provider, ProviderProfile,
      foreign_key: :provider_id,
      source: :provider_id,
      references: :id

    timestamps()
  end

  @type kind :: :community_agreement | :staff_attestation
  @type entity_type :: :individual | :business
  @type t :: %__MODULE__{}

  @doc """
  Insert changeset. `:id` and `:signed_at` are domain-provided by `new/1`. `:entity_type` is
  optional — historical rows predate the column and stay valid with a null value.
  """
  def changeset(%__MODULE__{} = agreement, attrs) do
    agreement
    |> cast(attrs, ~w(id provider_id kind entity_type signed_by_name signed_at version)a)
    |> validate_required(~w(provider_id kind signed_by_name signed_at version)a)
    |> foreign_key_constraint(:provider_id)
  end

  @doc """
  Builds a signed agreement from a provider's submission, stamping a fresh id and `signed_at`.

  `kind` defaults to `:community_agreement`. Returns `{:ok, agreement}` when `provider_id`,
  `signed_by_name` and `version` are all present and non-blank, otherwise `{:error, errors}`
  (a keyword list of `{field, message}`).
  """
  @spec new(map()) :: {:ok, t()} | {:error, keyword()}
  def new(attrs) when is_map(attrs) do
    case validate(attrs) do
      [] ->
        {:ok,
         %__MODULE__{
           id: Ecto.UUID.generate(),
           provider_id: attrs.provider_id,
           kind: Map.get(attrs, :kind, :community_agreement),
           entity_type: Map.get(attrs, :entity_type),
           signed_by_name: String.trim(attrs.signed_by_name),
           signed_at: DateTime.utc_now() |> DateTime.truncate(:second),
           version: attrs.version
         }}

      errors ->
        {:error, errors}
    end
  end

  defp validate(attrs) do
    []
    |> validate_present(attrs, :version)
    |> validate_present(attrs, :signed_by_name)
    |> validate_present(attrs, :provider_id)
  end

  defp validate_present(errors, attrs, key) do
    if blank?(Map.get(attrs, key)) do
      [{key, "is required"} | errors]
    else
      errors
    end
  end

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: true
end
