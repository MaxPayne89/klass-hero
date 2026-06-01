defmodule KlassHero.Family.Application.Commands.Consents.GrantConsent do
  @moduledoc """
  Use case for granting parental consent.

  Orchestrates domain validation and persistence through the repository port.
  """

  alias KlassHero.Family.Domain.Models.Consent
  alias KlassHero.Shared.CommandResult

  @repository Application.compile_env!(:klass_hero, [:family, :for_storing_consents])

  @doc """
  Grants a new consent record.

  Expects a map with :parent_id, :child_id, and :consent_type.
  Automatically sets :granted_at to current UTC time and generates an ID.

  Returns:
  - `{:ok, Consent.t()}` on success
  - `{:error, {:validation_error, errors}}` for domain validation failures
  - `{:error, changeset}` for persistence validation failures
  """
  def execute(attrs) when is_map(attrs) do
    attrs_with_defaults =
      attrs
      |> Map.put_new(:id, Ecto.UUID.generate())
      |> Map.put_new(:granted_at, DateTime.utc_now())

    with {:ok, _validated} <- Consent.new(attrs_with_defaults),
         {:ok, persisted} <- @repository.grant(attrs_with_defaults) do
      {:ok, persisted}
    else
      result -> CommandResult.wrap_validation_errors(result)
    end
  end
end
