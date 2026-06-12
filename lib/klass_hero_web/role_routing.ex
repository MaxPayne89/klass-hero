defmodule KlassHeroWeb.RoleRouting do
  @moduledoc """
  Single source of truth for resolving a user's role to their landing surface.

  Role precedence is `provider > staff > parent` (a person who is both a provider
  and a staff member — ADR-0005 — lands on the provider surface). Every place
  that maps a role to a dashboard or messages path delegates here so the next
  role or path change touches one module, not five.

  Takes a plain roles list, so it works for both `User.intended_roles` (the
  signup-intent / landing hint) and a resolved `Scope.roles` (persona existence).
  """

  use KlassHeroWeb, :verified_routes

  @doc """
  Returns the highest-precedence known role in `roles`, or `nil` if none.
  """
  @spec primary_role([atom()]) :: :provider | :staff | :parent | nil
  def primary_role(roles) when is_list(roles) do
    cond do
      :provider in roles -> :provider
      :staff in roles -> :staff
      :parent in roles -> :parent
      true -> nil
    end
  end

  @doc "The dashboard path for the highest-precedence role in `roles`."
  @spec dashboard_path([atom()]) :: String.t()
  def dashboard_path(roles) do
    case primary_role(roles) do
      :provider -> ~p"/provider/dashboard"
      :staff -> ~p"/staff/dashboard"
      _ -> ~p"/dashboard"
    end
  end

  @doc "The messages path for the highest-precedence role in `roles`."
  @spec messages_path([atom()]) :: String.t()
  def messages_path(roles) do
    case primary_role(roles) do
      :provider -> ~p"/provider/messages"
      :staff -> ~p"/staff/messages"
      _ -> ~p"/messages"
    end
  end
end
