defmodule KlassHero.Enrollment.ClaimInvite do
  @moduledoc """
  Use case for claiming a bulk enrollment invite by token.

  Validates the token, resolves or creates the user account, and publishes
  the `:invite_claimed` event to trigger the async saga (child creation,
  enrollment).
  """

  alias KlassHero.Accounts
  alias KlassHero.Enrollment
  alias KlassHero.Enrollment.BulkEnrollmentInvite
  alias KlassHero.Enrollment.ClaimResult
  alias KlassHero.Enrollment.Domain.Events.EnrollmentEvents
  alias KlassHero.Shared.EventDispatchHelper
  alias KlassHero.Shared.Outbox

  require Logger

  @doc """
  Claims an invite by its token.

  Returns:
  - `{:ok, %ClaimResult{user_type: :new_user, user: user, invite: invite}}` — new account created
  - `{:ok, %ClaimResult{user_type: :existing_user, user: user, invite: invite}}` — existing account found
  - `{:error, :not_found}` — invalid or expired token
  - `{:error, :already_claimed}` — invite already processed
  """
  @spec execute(binary()) ::
          {:ok, ClaimResult.t()}
          | {:error, :not_found | :already_claimed | term()}
  def execute(token) when is_binary(token) do
    with {:ok, invite} <- Enrollment.get_invite_by_token(token),
         {:ok, invite} <- BulkEnrollmentInvite.ensure_claimable(invite),
         {:ok, user_type, user} <- resolve_user(invite),
         {:ok, result} <- build_and_publish(invite, user_type, user) do
      Logger.info("[ClaimInvite] Claimed invite",
        invite_id: invite.id,
        user_type: user_type,
        user_id: user.id
      )

      {:ok, result}
    end
  end

  # Returning parents must not get a duplicate account — link invite to existing user and skip onboarding.
  defp resolve_user(invite) do
    case Accounts.get_user_by_email(invite.guardian_email) do
      %{} = user ->
        {:ok, :existing_user, to_user_result(user)}

      nil ->
        register_new_user(invite)
    end
  end

  defp register_new_user(invite) do
    attrs = %{
      name: guardian_name(invite),
      email: invite.guardian_email,
      intended_roles: [:parent]
    }

    case Accounts.register_user(attrs) do
      {:ok, user} -> {:ok, :new_user, to_user_result(user)}
      {:error, reason} -> {:error, reason}
    end
  end

  # Narrow the Accounts.User struct to a lightweight map so Enrollment's public
  # ClaimResult never leaks an %Accounts.User{} type across the context boundary.
  defp to_user_result(user), do: %{id: user.id, email: user.email, name: user.name}

  defp guardian_name(invite) do
    case {invite.guardian_first_name, invite.guardian_last_name} do
      {nil, nil} -> invite.guardian_email
      {first, nil} -> first
      {nil, last} -> last
      {first, last} -> "#{first} #{last}"
    end
  end

  @spec build_and_publish(BulkEnrollmentInvite.t(), ClaimResult.user_type(), map()) ::
          {:ok, ClaimResult.t()} | {:error, term()}
  defp build_and_publish(invite, user_type, user) do
    invite.id
    |> EnrollmentEvents.invite_claimed(%{
      invite_id: invite.id,
      user_id: user.id,
      program_id: invite.program_id,
      provider_id: invite.provider_id,
      child_first_name: invite.child_first_name,
      child_last_name: invite.child_last_name,
      child_date_of_birth: invite.child_date_of_birth,
      guardian_email: invite.guardian_email,
      guardian_first_name: invite.guardian_first_name,
      guardian_last_name: invite.guardian_last_name,
      school_grade: invite.school_grade,
      school_name: invite.school_name,
      medical_conditions: invite.medical_conditions,
      nut_allergy: invite.nut_allergy,
      consent_photo_marketing: invite.consent_photo_marketing,
      consent_photo_social_media: invite.consent_photo_social_media
    })
    |> stage_and_dispatch(%ClaimResult{user_type: user_type, user: user, invite: invite})
  end

  # This one has no local write to join a transaction: the invite is marked registered
  # by MarkInviteRegistered, a priority-5 handler the dispatch below triggers, and
  # Promote sat behind it at priority 10. So the order is dispatch first, then stage.
  # Collapsing the two into one transaction means inlining that handler, which belongs
  # with deleting the bus.
  #
  # Staging is deliberately not gated on the dispatch result: the bus ran every
  # registered handler regardless of what an earlier one returned, so gating here
  # would newly let a MarkInviteRegistered failure suppress the whole cross-context
  # onboarding chain. The dispatch result still decides what the caller gets back.
  defp stage_and_dispatch(event, result) do
    dispatch_result = EventDispatchHelper.dispatch_or_ok(event, KlassHero.Enrollment, result)
    Outbox.stage(KlassHero.Enrollment, event)
    dispatch_result
  end
end
