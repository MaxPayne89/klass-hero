defmodule KlassHero.Enrollment.Adapters.Driven.Accounts.UserAccountResolver do
  @moduledoc """
  Adapter that resolves user accounts by delegating to the Accounts context.

  Maps the Accounts `User` struct to a lightweight map so Enrollment
  never depends on Accounts domain types.
  """

  alias KlassHero.Accounts

  def get_user_by_email(email) do
    case Accounts.get_user_by_email(email) do
      %{} = user -> to_user_result(user)
      nil -> nil
    end
  end

  def register_user(attrs) do
    case Accounts.register_user(attrs) do
      {:ok, user} -> {:ok, to_user_result(user)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp to_user_result(user) do
    %{id: user.id, email: user.email, name: user.name}
  end
end
