defmodule KlassHero.Enrollment.Adapters.Driven.Persistence.Mappers.ParticipantPolicyMapper do
  @moduledoc """
  Maps between `ParticipantPolicySchema` (Ecto) and `ParticipantPolicy` (domain).
  """

  alias KlassHero.Enrollment.Adapters.Driven.Persistence.Schemas.ParticipantPolicySchema
  alias KlassHero.Enrollment.Domain.Models.ParticipantPolicy

  @known_keys ~w(program_id eligibility_at min_age_months max_age_months allowed_genders min_grade max_grade)a

  @doc """
  Converts a `ParticipantPolicySchema` to a domain `ParticipantPolicy`. UUIDs are stringified.
  """
  @spec to_domain(ParticipantPolicySchema.t()) :: ParticipantPolicy.t()
  def to_domain(%ParticipantPolicySchema{} = schema) do
    %ParticipantPolicy{
      id: to_string(schema.id),
      program_id: to_string(schema.program_id),
      eligibility_at: schema.eligibility_at,
      min_age_months: schema.min_age_months,
      max_age_months: schema.max_age_months,
      allowed_genders: schema.allowed_genders || [],
      min_grade: schema.min_grade,
      max_grade: schema.max_grade,
      inserted_at: schema.inserted_at,
      updated_at: schema.updated_at
    }
  end

  @doc """
  Filters `attrs` to only known participant policy keys present in the input.

  Omitting absent keys preserves schema defaults (e.g. `eligibility_at: "registration"`) —
  mapping missing keys as `nil` would override those defaults during `cast`.
  """
  @spec to_schema_attrs(map()) :: map()
  def to_schema_attrs(attrs) when is_map(attrs) do
    @known_keys
    |> Enum.filter(&Map.has_key?(attrs, &1))
    |> Map.new(fn key -> {key, attrs[key]} end)
  end
end
