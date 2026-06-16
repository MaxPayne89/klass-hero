defmodule KlassHero.Provider.Adapters.Driven.Persistence.Schemas.VerificationStepSchema do
  @moduledoc """
  Ecto schema for the verification_steps table — one row per Verification Step of a Vetting Case.

  Use `VerificationStepMapper` to convert between this schema and the domain `VerificationStep`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.Accounts.User
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.VettingCaseSchema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "verification_steps" do
    field :key, :string
    field :status, :string, default: "not_started"
    field :completed_via, :string
    field :requires, {:array, :string}, default: []
    field :admin_review, :boolean, default: false
    field :evidence_ref, :binary_id
    field :rejection_reason, :string
    field :reviewed_at, :utc_datetime_usec
    field :submitted_at, :utc_datetime_usec

    belongs_to :vetting_case, VettingCaseSchema
    belongs_to :reviewed_by, User

    timestamps()
  end

  @doc "Changeset for insert/update of a verification step."
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [
      :vetting_case_id,
      :key,
      :status,
      :completed_via,
      :requires,
      :admin_review,
      :evidence_ref,
      :rejection_reason,
      :reviewed_by_id,
      :reviewed_at,
      :submitted_at
    ])
    |> validate_required([:vetting_case_id, :key, :status, :completed_via])
    |> validate_inclusion(:status, ~w(not_started submitted approved rejected))
    |> unique_constraint([:vetting_case_id, :key])
  end
end
