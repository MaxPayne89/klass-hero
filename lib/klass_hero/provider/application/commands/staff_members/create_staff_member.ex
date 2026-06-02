defmodule KlassHero.Provider.Application.Commands.StaffMembers.CreateStaffMember do
  @moduledoc """
  Use case for creating a new staff member.

  Orchestrates domain validation and persistence through the repository port.

  ## Return values

  - `{:ok, staff_member}` — staff member without email (display-only, no invitation)
  - `{:ok, staff_member, raw_token}` — staff member with email; invitation token generated,
    `:staff_member_invited` integration event emitted
  """

  alias KlassHero.Provider.Application.InvitationEmitter
  alias KlassHero.Provider.Domain.Models.StaffMember
  alias KlassHero.Shared.CommandResult

  require Logger

  @repository Application.compile_env!(:klass_hero, [:provider, :for_storing_staff_members])

  def execute(attrs) when is_map(attrs) do
    attrs_with_id = Map.put_new(attrs, :id, Ecto.UUID.generate())

    if has_email?(attrs_with_id) do
      execute_with_invitation(attrs_with_id)
    else
      execute_display_only(attrs_with_id)
    end
  end

  defp has_email?(attrs) do
    case attrs[:email] || attrs["email"] do
      nil -> false
      "" -> false
      email when is_binary(email) -> String.trim(email) != ""
      _other -> false
    end
  end

  defp execute_display_only(attrs) do
    with {:ok, _validated} <- StaffMember.new(attrs),
         {:ok, persisted} <- @repository.create(attrs) do
      {:ok, persisted}
    else
      result -> CommandResult.wrap_validation_errors(result)
    end
  end

  defp execute_with_invitation(attrs) do
    {raw_token, token_hash} = StaffMember.generate_invitation_token()

    attrs_with_invitation =
      attrs
      |> Map.put(:invitation_status, :pending)
      |> Map.put(:invitation_token_hash, token_hash)

    persistence_attrs = Map.update!(attrs_with_invitation, :invitation_status, &to_string/1)

    with {:ok, _validated} <- StaffMember.new(attrs_with_invitation),
         {:ok, persisted} <- @repository.create(persistence_attrs) do
      case InvitationEmitter.emit(persisted, raw_token) do
        :ok ->
          {:ok, persisted, raw_token}

        {:error, reason} ->
          compensate_failed_emission(persisted, reason)
      end
    else
      result -> CommandResult.wrap_validation_errors(result)
    end
  end

  defp compensate_failed_emission(staff_member, reason) do
    Logger.warning("[CreateStaffMember] Event emission failed, compensating",
      staff_member_id: staff_member.id,
      reason: inspect(reason)
    )

    with {:ok, failed} <- StaffMember.transition_invitation(staff_member, :failed),
         {:ok, _persisted} <- @repository.update(failed) do
      {:error, :invitation_emission_failed}
    else
      {:error, _compensation_error} ->
        Logger.error("[CreateStaffMember] Compensation failed",
          staff_member_id: staff_member.id
        )

        {:error, :invitation_emission_failed}
    end
  end
end
