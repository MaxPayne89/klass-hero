defmodule KlassHero.Accounts.Application.Commands.AnonymizeUser do
  @moduledoc """
  Use case for GDPR account anonymization. Anonymizes PII, deletes tokens,
  and publishes `user_anonymized` for downstream cascade.
  """

  alias KlassHero.Accounts.Domain.Events.UserEvents
  alias KlassHero.Shared.EventDispatchHelper

  @user_repository Application.compile_env!(
                     :klass_hero,
                     [:accounts, :for_storing_users]
                   )

  @doc """
  Anonymizes a user account.

  Returns `{:ok, %User{}}`, `{:error, :user_not_found}`, or `{:error, changeset}`.
  """
  def execute(%{email: _} = user) do
    previous_email = user.email

    case @user_repository.anonymize(user) do
      {:ok, anonymized_user} ->
        UserEvents.user_anonymized(anonymized_user, %{previous_email: previous_email})
        |> EventDispatchHelper.dispatch(KlassHero.Accounts)

        {:ok, anonymized_user}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def execute(nil), do: {:error, :user_not_found}
end
