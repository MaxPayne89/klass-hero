defmodule KlassHero.Provider.Adapters.Driven.Persistence.Schemas.VettingCaseSchema do
  @moduledoc """
  Ecto schema for the vetting_cases table — one row per Provider's Vetting Case.

  Owns its `verification_steps`. Use `VettingCaseMapper` to convert between this schema and the
  domain `VettingCase`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.ProviderProfileSchema
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.VerificationStepSchema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "vetting_cases" do
    field :entity_type, :string
    field :lifecycle, :string, default: "not_started"

    belongs_to :provider, ProviderProfileSchema
    has_many :steps, VerificationStepSchema, foreign_key: :vetting_case_id

    timestamps()
  end

  @doc "Changeset for insert/update of a vetting case."
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:provider_id, :entity_type, :lifecycle])
    |> validate_required([:provider_id, :entity_type, :lifecycle])
    |> validate_inclusion(:entity_type, ~w(individual business))
    |> validate_inclusion(:lifecycle, ~w(not_started in_progress verified))
    |> unique_constraint(:provider_id)
  end
end
