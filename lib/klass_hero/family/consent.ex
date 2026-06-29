defmodule KlassHero.Family.Consent do
  @moduledoc """
  A parental consent record in the Family context.

  Multiple records per (child, consent_type) are allowed for audit history;
  the active consent is the one with `withdrawn_at == nil` (enforced by a
  partial unique index). The Ecto schema is the domain struct; validation lives
  in the changeset.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.Family.Child
  alias KlassHero.Family.ParentProfile

  @valid_consent_types ~w(provider_data_sharing photo_marketing photo_social_media medical participation)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "consents" do
    belongs_to :parent, ParentProfile
    belongs_to :child, Child

    field :consent_type, :string
    field :granted_at, :utc_datetime
    field :withdrawn_at, :utc_datetime

    timestamps()
  end

  @doc "The valid consent type values."
  def valid_consent_types, do: @valid_consent_types

  @doc "Whether the consent is still active (not withdrawn)."
  def active?(%__MODULE__{withdrawn_at: nil}), do: true
  def active?(%__MODULE__{}), do: false

  @doc """
  Changeset for granting a consent record.

  `parent_id` / `child_id` are set programmatically (not cast) for safety. The
  partial unique index on (child_id, consent_type) WHERE withdrawn_at IS NULL
  prevents a second active consent of the same type.
  """
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:consent_type, :granted_at])
    |> put_change(:parent_id, attrs[:parent_id])
    |> put_change(:child_id, attrs[:child_id])
    |> validate_required([:parent_id, :child_id, :consent_type, :granted_at])
    |> validate_length(:consent_type, max: 100)
    |> validate_inclusion(:consent_type, @valid_consent_types)
    |> foreign_key_constraint(:parent_id)
    |> foreign_key_constraint(:child_id)
    |> unique_constraint(:consent_type,
      name: :consents_active_child_consent_type_index,
      message: "already has an active consent of this type"
    )
  end

  @doc "Changeset that withdraws a consent by stamping `withdrawn_at`."
  def withdraw_changeset(schema, %DateTime{} = withdrawn_at) do
    change(schema, %{withdrawn_at: withdrawn_at})
  end

  @doc "No-op changeset required by Backpex even when edit is disabled via `can?/3`."
  def admin_changeset(schema, _attrs, _metadata), do: change(schema)

  @type t :: %__MODULE__{
          id: binary() | nil,
          parent_id: binary() | nil,
          child_id: binary() | nil,
          consent_type: String.t() | nil,
          granted_at: DateTime.t() | nil,
          withdrawn_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }
end
