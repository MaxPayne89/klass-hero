defmodule KlassHero.Provider.Adapters.Driven.Persistence.Mappers.IdentityVerificationMapper do
  @moduledoc """
  Bidirectional mapping between the `IdentityVerification` domain model and its Ecto schema.
  Status and outcome atoms are stored as strings; `outcome` is nil while a session is processing.
  """

  import KlassHero.Shared.Adapters.Driven.Persistence.MapperHelpers, only: [maybe_add_id: 2]

  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.IdentityVerificationSchema
  alias KlassHero.Provider.Domain.Models.IdentityVerification

  @doc "Converts an IdentityVerificationSchema to the domain model."
  def to_domain(%IdentityVerificationSchema{} = schema) do
    %IdentityVerification{
      id: to_string(schema.id),
      provider_id: to_string(schema.provider_id),
      stripe_session_id: schema.stripe_session_id,
      status: String.to_existing_atom(schema.status),
      outcome: string_to_outcome(schema.outcome),
      failure_reason: schema.failure_reason,
      verified_at: schema.verified_at
    }
  end

  @doc "Converts a domain IdentityVerification to a schema attributes map."
  def to_schema(%IdentityVerification{} = iv) do
    %{
      provider_id: iv.provider_id,
      stripe_session_id: iv.stripe_session_id,
      status: Atom.to_string(iv.status),
      outcome: outcome_to_string(iv.outcome),
      failure_reason: iv.failure_reason,
      verified_at: iv.verified_at
    }
    |> maybe_add_id(iv.id)
  end

  defp string_to_outcome(nil), do: nil
  defp string_to_outcome(outcome), do: String.to_existing_atom(outcome)

  defp outcome_to_string(nil), do: nil
  defp outcome_to_string(outcome), do: Atom.to_string(outcome)
end
