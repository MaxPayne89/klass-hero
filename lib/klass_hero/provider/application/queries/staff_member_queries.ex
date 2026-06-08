defmodule KlassHero.Provider.Application.Queries.StaffMemberQueries do
  @moduledoc """
  Query module for staff member reads.

  Centralises all read operations that depend on the staff member repository,
  keeping the facade free of direct repository references.
  """

  alias KlassHero.Provider.Domain.Models.StaffMember

  @staff_repository Application.compile_env!(:klass_hero, [
                      :provider,
                      :for_querying_staff_members
                    ])

  @doc """
  Retrieves a single staff member by ID.
  """
  @spec get(String.t()) :: {:ok, StaffMember.t()} | {:error, :not_found}
  def get(staff_id) when is_binary(staff_id) do
    @staff_repository.get(staff_id)
  end

  @doc """
  Lists all staff members for a provider, ordered by insertion date.
  """
  @spec list_by_provider(String.t()) :: {:ok, [StaffMember.t()]}
  def list_by_provider(provider_id) when is_binary(provider_id) do
    @staff_repository.list_by_provider(provider_id)
  end

  @doc """
  Lists active staff members for a provider.
  """
  @spec list_active_by_provider(String.t()) :: {:ok, [StaffMember.t()]}
  def list_active_by_provider(provider_id) when is_binary(provider_id) do
    @staff_repository.list_active_by_provider(provider_id)
  end

  @doc """
  Lists active staff members assigned to a program, hydrated from the join table
  in a single query.
  """
  @spec list_active_by_program(String.t()) :: {:ok, [StaffMember.t()]}
  def list_active_by_program(program_id) when is_binary(program_id) do
    @staff_repository.list_active_by_program(program_id)
  end

  @doc """
  Returns the active staff member record linked to the given user ID.
  Used by Scope to resolve :staff role.
  """
  @spec get_active_by_user(String.t()) :: {:ok, StaffMember.t()} | {:error, :not_found}
  def get_active_by_user(user_id) when is_binary(user_id) do
    @staff_repository.get_active_by_user(user_id)
  end

  @doc """
  Returns true if the given user has any active staff_member row for the given provider.

  Used by Messaging to authorise broadcast follow-ups for staff who work for
  the broadcast's provider, without depending on the per-program staff
  projection. Filters by both `provider_id` and `user_id` so a user with
  active staff_members at multiple providers is correctly identified for each.
  """
  @spec active_for_provider_and_user?(String.t(), String.t()) :: boolean()
  def active_for_provider_and_user?(provider_id, user_id) when is_binary(provider_id) and is_binary(user_id) do
    @staff_repository.active_for_provider_and_user?(provider_id, user_id)
  end

  @doc """
  Returns the staff member matching the given invitation token hash,
  only if invitation_status is :sent. Used by the invitation registration flow.
  """
  @spec get_by_token_hash(binary()) :: {:ok, StaffMember.t()} | {:error, :not_found}
  def get_by_token_hash(token_hash) when is_binary(token_hash) do
    @staff_repository.get_by_token_hash(token_hash)
  end
end
