defmodule KlassHero.Family.Adapters.Driven.Persistence.Schemas.ConsentSchema do
  @moduledoc """
  Ecto schema for the consents table.

  Maps the consents database table to an Elixir struct with validation.
  Use ConsentMapper for domain entity conversion.

  ## Fields

  - `id` - Binary UUID primary key
  - `parent_id` - Foreign key to parents table
  - `child_id` - Foreign key to children table
  - `consent_type` - Type of consent (e.g. "provider_data_sharing")
  - `granted_at` - When consent was granted
  - `withdrawn_at` - When consent was withdrawn (nil if still active)
  - `inserted_at` - Timestamp when record was created
  - `updated_at` - Timestamp when record was last updated
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.Family.Child
  alias KlassHero.Family.Domain.Models.Consent
  alias KlassHero.Family.ParentProfile

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "consents" do
    belongs_to :parent,
               ParentProfile

    belongs_to :child,
               Child

    field :consent_type, :string
    field :granted_at, :utc_datetime
    field :withdrawn_at, :utc_datetime

    timestamps()
  end

  @doc """
  Changeset for granting a new consent record.

  ## Validations

  - Required: parent_id, child_id, consent_type, granted_at
  - consent_type: max 100 characters
  - Foreign key constraints on parent_id and child_id
  """
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:consent_type, :granted_at])
    |> put_change(:parent_id, attrs[:parent_id])
    |> put_change(:child_id, attrs[:child_id])
    |> validate_required([:parent_id, :child_id, :consent_type, :granted_at])
    |> validate_length(:consent_type, max: 100)
    |> validate_inclusion(:consent_type, Consent.valid_consent_types())
    |> foreign_key_constraint(:parent_id)
    |> foreign_key_constraint(:child_id)
    |> unique_constraint(:consent_type,
      name: :consents_active_child_consent_type_index,
      message: "already has an active consent of this type"
    )
  end

  @doc """
  Changeset for withdrawing a consent record (setting withdrawn_at).
  """
  def withdraw_changeset(schema, %DateTime{} = withdrawn_at) do
    schema
    |> change(%{withdrawn_at: withdrawn_at})
  end

  @doc """
  No-op changeset required by Backpex even when edit is disabled via `can?/3`.
  """
  def admin_changeset(schema, _attrs, _metadata), do: change(schema)
end
