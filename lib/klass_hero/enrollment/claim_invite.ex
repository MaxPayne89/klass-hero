defmodule KlassHero.Enrollment.ClaimInvite do
  @moduledoc """
  Use case for claiming a bulk enrollment invite by token.

  Validates the token, resolves or creates the user account, then marks the invite
  registered and stages `:invite_claimed` in one transaction — the event drives the
  rest of the saga (child creation, enrollment) through the outbox.
  """

  alias KlassHero.Accounts
  alias KlassHero.Enrollment
  alias KlassHero.Enrollment.BulkEnrollmentInvite
  alias KlassHero.Enrollment.ClaimResult
  alias KlassHero.Enrollment.Domain.Events.EnrollmentEvents
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
    |> register_and_stage(invite, %ClaimResult{user_type: user_type, user: user, invite: invite})
  end

  # Marking the invite registered and announcing the claim are one fact. They used to
  # be two: a `MarkInviteRegistered` handler ran the transition during dispatch, and
  # staging followed it ungated, so a staging failure left a registered invite no
  # consumer ever heard about.
  #
  # `register_claimed_invite/1` re-checks claimability on the row as it stands inside
  # this transaction. `ensure_claimable/1` ran back at the top of `execute/1`, and two
  # concurrent claims of one token both clear it — the loser has to be told the invite
  # is spoken for, not handed a transition error.
  defp register_and_stage(event, invite, result) do
    Outbox.transact(KlassHero.Enrollment, fn ->
      with {:ok, _registered} <- Enrollment.register_claimed_invite(invite.id) do
        {:ok, result, [event]}
      end
    end)
  end
end
