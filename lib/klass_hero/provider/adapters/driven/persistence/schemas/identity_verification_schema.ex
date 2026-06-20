defmodule KlassHero.Provider.Adapters.Driven.Persistence.Schemas.IdentityVerificationSchema do
  @moduledoc """
  Ecto schema for the identity_verifications table — one row per Stripe Identity session.

  Stores only the session id and pass/fail outcome (ADR-0007); never a DOB or document images.
  Use `IdentityVerificationMapper` to convert between this schema and the domain model.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.ProviderProfileSchema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "identity_verifications" do
    field :stripe_session_id, :string
    field :status, :string, default: "processing"
    field :outcome, :string
    field :failure_reason, :string
    field :verified_at, :utc_datetime_usec

    belongs_to :provider, ProviderProfileSchema

    timestamps()
  end

  @doc "Changeset for insert/update of an identity verification. `:id` is domain-provided."
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:id, :provider_id, :stripe_session_id, :status, :outcome, :failure_reason, :verified_at])
    |> validate_required([:provider_id, :stripe_session_id, :status])
    |> validate_inclusion(:status, ~w(processing verified requires_input canceled))
    |> validate_inclusion(:outcome, ~w(pass fail))
    |> unique_constraint(:stripe_session_id)
  end
end
