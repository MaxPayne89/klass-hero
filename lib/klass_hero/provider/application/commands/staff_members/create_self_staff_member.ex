defmodule KlassHero.Provider.Application.Commands.StaffMembers.CreateSelfStaffMember do
  @moduledoc """
  Use case for a provider deliberately staffing themselves (#969, ADR-0005).

  Only a StaffMember is assignable to Programs, so a founder who teaches adds
  themselves to their own team. The row is born already linked: `user_id` set,
  `invitation_status: :accepted`, no invitation token, no `invitation_sent_at`,
  and — unlike `CreateStaffMember` — no `:staff_member_invited` event, so no
  invitation email ever fires for the person who already owns the account.

  Duplicate self-staffing is guarded by the active-row check below; there is no
  DB unique constraint on (provider_id, user_id) (multi-employer staff need
  multiple rows per user), so a concurrent double-submit can race past it.
  Accepted: the loser is a visible duplicate the provider can delete.
  """

  alias KlassHero.Provider.Domain.Models.StaffMember
  alias KlassHero.Shared.CommandResult

  @query Application.compile_env!(:klass_hero, [:provider, :for_querying_staff_members])
  @repository Application.compile_env!(:klass_hero, [:provider, :for_storing_staff_members])

  @doc """
  Creates the provider's own staff row, pre-linked and accepted.

  Returns `{:error, :already_staffed}` when an active row already links this
  user to this provider.
  """
  @spec execute(String.t(), String.t(), map()) ::
          {:ok, StaffMember.t()} | {:error, :already_staffed | term()}
  def execute(provider_id, user_id, attrs) when is_binary(provider_id) and is_binary(user_id) and is_map(attrs) do
    if @query.active_for_provider_and_user?(provider_id, user_id) do
      {:error, :already_staffed}
    else
      create_linked_member(provider_id, user_id, attrs)
    end
  end

  defp create_linked_member(provider_id, user_id, attrs) do
    domain_attrs =
      attrs
      |> Map.put_new(:id, Ecto.UUID.generate())
      |> Map.put(:provider_id, provider_id)
      |> Map.put(:user_id, user_id)
      |> Map.put(:invitation_status, :accepted)

    persistence_attrs = Map.update!(domain_attrs, :invitation_status, &to_string/1)

    with {:ok, _validated} <- StaffMember.new(domain_attrs),
         {:ok, persisted} <- @repository.create(persistence_attrs) do
      {:ok, persisted}
    else
      result -> CommandResult.wrap_validation_errors(result)
    end
  end
end
