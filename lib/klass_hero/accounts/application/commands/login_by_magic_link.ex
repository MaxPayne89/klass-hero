defmodule KlassHero.Accounts.Application.Commands.LoginByMagicLink do
  @moduledoc """
  Use case for logging in a user via magic link token.

  Handles three scenarios:
  1. Confirmed user — logs in, expires magic link token
  2. Unconfirmed user (no password) — confirms email, logs in, expires all tokens
  3. Unconfirmed user (has password) — security violation error
  """

  alias KlassHero.Accounts.Domain.Events.UserEvents
  alias KlassHero.Shared.EventDispatchHelper

  @user_repository Application.compile_env!(
                     :klass_hero,
                     [:accounts, :for_storing_users]
                   )

  @doc """
  Logs in a user by magic link token.

  Returns `{:ok, {%User{}, expired_tokens}}`, `{:error, :not_found}`,
  `{:error, :invalid_token}`, or `{:error, :security_violation}`.
  """
  def execute(token) when is_binary(token) do
    case @user_repository.resolve_magic_link(token) do
      {:ok, {:unconfirmed, user}} ->
        handle_unconfirmed(user)

      {:ok, {:confirmed, user, token_record}} ->
        handle_confirmed(user, token_record)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # First login for unconfirmed user: confirm email, expire all tokens, dispatch event
  defp handle_unconfirmed(user) do
    case @user_repository.confirm_and_cleanup_tokens(user) do
      {:ok, {confirmed_user, tokens}} ->
        UserEvents.user_confirmed(confirmed_user, %{confirmation_method: :magic_link})
        |> EventDispatchHelper.dispatch(KlassHero.Accounts)

        {:ok, {confirmed_user, tokens}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_confirmed(user, token_record) do
    @user_repository.delete_token(token_record)
    {:ok, {user, []}}
  end
end
