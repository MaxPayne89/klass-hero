defmodule KlassHeroWeb.Helpers.FamilyHelpers do
  @moduledoc """
  Shared helpers for working with family data in LiveViews.
  """

  alias KlassHero.Family

  @doc "Returns children for the current user's parent profile, or `[]` if none exists."
  def get_children_for_current_user(socket) do
    with %{current_scope: %{user: %{id: identity_id}}} <- socket.assigns,
         {:ok, parent} <- Family.get_parent_by_identity(identity_id) do
      Family.get_children(parent.id)
    else
      %{} -> []
      {:error, :not_found} -> []
    end
  end

  @doc """
  Retrieves the parent profile for the current user from socket assigns.

  Returns:
  - `{:ok, parent}` if parent profile exists
  - `{:error, :no_parent}` if no parent profile or no user in scope
  """
  def get_parent_for_current_user(socket) do
    with %{current_scope: %{user: %{id: identity_id}}} <- socket.assigns,
         {:ok, parent} <- Family.get_parent_by_identity(identity_id) do
      {:ok, parent}
    else
      %{} -> {:error, :no_parent}
      {:error, :not_found} -> {:error, :no_parent}
    end
  end
end
