defmodule KlassHero.Provider.Domain.Ports.ForQueryingStaffMembers do
  @moduledoc """
  Read-only port for querying staff members in the Provider bounded context.

  Separated from `ForStoringStaffMembers` (write-only) to support CQRS at
  the port level. Read operations never mutate state.
  """

  alias KlassHero.Provider.Domain.Models.StaffMember
  alias KlassHero.Provider.Domain.ReadModels.StaffMembership

  @callback get(id :: binary()) ::
              {:ok, StaffMember.t()} | {:error, :not_found}

  @callback list_by_provider(provider_id :: binary()) ::
              {:ok, [StaffMember.t()]}

  @callback list_active_by_provider(provider_id :: binary()) ::
              {:ok, [StaffMember.t()]}

  @callback list_active_by_program(program_id :: binary()) ::
              {:ok, [StaffMember.t()]}

  @callback get_by_token_hash(token_hash :: binary()) ::
              {:ok, StaffMember.t()} | {:error, :not_found}

  @callback get_active_by_user(user_id :: String.t()) ::
              {:ok, StaffMember.t()} | {:error, :not_found}

  @callback list_active_memberships_by_user(user_id :: String.t()) ::
              {:ok, [StaffMembership.t()]}

  @callback active_for_provider_and_user?(provider_id :: String.t(), user_id :: String.t()) ::
              boolean()
end
