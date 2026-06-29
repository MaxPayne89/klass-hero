defmodule KlassHero.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `KlassHero.Accounts` context.
  """

  import Ecto.Query

  alias KlassHero.Accounts
  alias KlassHero.Accounts.Scope

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"
  def unique_user_name, do: "Test User #{System.unique_integer()}"

  def valid_user_attributes(attrs \\ %{}) do
    attrs_map = Map.new(attrs)
    name = Map.get(attrs_map, :name, unique_user_name())

    Map.merge(
      %{
        email: unique_user_email(),
        name: name,
        intended_roles: [:parent]
      },
      attrs_map
    )
  end

  def unconfirmed_user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Accounts.register_user()

    user
  end

  def user_fixture(attrs \\ %{}) do
    # Extract is_admin before passing to registration (since registration_changeset
    # doesn't cast is_admin for security reasons)
    attrs_map = Map.new(attrs)
    {is_admin, registration_attrs} = Map.pop(attrs_map, :is_admin)

    user = unconfirmed_user_fixture(registration_attrs)

    token =
      extract_user_token(fn url ->
        Accounts.deliver_login_instructions(user, url)
      end)

    {:ok, {user, _expired_tokens}} =
      Accounts.login_user_by_magic_link(token)

    # Set is_admin directly if provided (bypasses registration changeset)
    # Trigger: test fixtures need to create admin users
    # Why: registration_changeset doesn't cast is_admin for security
    # Outcome: test user has is_admin set as requested
    if is_admin do
      {:ok, user} =
        user
        |> Ecto.Changeset.change(is_admin: is_admin)
        |> KlassHero.Repo.update()

      user
    else
      user
    end
  end

  def user_scope_fixture do
    user = user_fixture()
    user_scope_fixture(user)
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  def set_password(user) do
    {:ok, {user, _expired_tokens}} =
      Accounts.update_user_password(user, %{password: valid_user_password()})

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    KlassHero.Repo.update_all(
      from(t in Accounts.UserToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  def generate_user_magic_link_token(user) do
    {encoded_token, user_token} = Accounts.UserToken.build_email_token(user, "login")
    KlassHero.Repo.insert!(user_token)
    {encoded_token, user_token.token}
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    KlassHero.Repo.update_all(
      from(ut in Accounts.UserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end
end
