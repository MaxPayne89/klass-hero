defmodule KlassHero.Messaging.Adapters.Driven.Accounts.UserResolver do
  @moduledoc """
  Adapter for resolving user information in the Messaging bounded context.

  Provides user display name resolution (via Accounts) and
  provider-to-user ID mapping (via Provider facade) for
  messaging UI and permission checks.
  """
  use KlassHero.Shared.Tracing

  import Ecto.Query

  alias KlassHero.Accounts.User
  alias KlassHero.Repo

  @spec get_display_names([String.t()]) :: {:ok, %{String.t() => String.t()}}
  def get_display_names([]), do: {:ok, %{}}

  def get_display_names(user_ids) do
    acl_span source: "messaging", target: "accounts" do
      names_map =
        from(u in User,
          where: u.id in ^user_ids,
          select: {u.id, u.name, u.email}
        )
        |> Repo.all()
        |> Map.new(fn {id, name, email} -> {id, name || email} end)

      {:ok, names_map}
    end
  end

  @spec get_display_name(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def get_display_name(user_id) do
    acl_span source: "messaging", target: "accounts" do
      case Repo.one(from(u in User, where: u.id == ^user_id, select: {u.name, u.email})) do
        nil -> {:error, :not_found}
        {name, email} -> {:ok, name || email}
      end
    end
  end

  @spec get_user_id_for_provider(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def get_user_id_for_provider(provider_id) do
    acl_span source: "messaging", target: "accounts" do
      # Delegate to Provider facade — Messaging cannot query Provider schemas directly.
      KlassHero.Provider.get_identity_id_for_provider(provider_id)
    end
  end
end
