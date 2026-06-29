defmodule KlassHero.Accounts.LoginByMagicLinkTest do
  @moduledoc """
  Integration tests for `Accounts.login_user_by_magic_link/1`.

  Covers the three paths:
  1. Confirmed user    — deletes the specific token, returns {user, []}
  2. Unconfirmed user  — confirms email, deletes all tokens, returns {user, expired_tokens}
  3. Error cases       — invalid/malformed/expired tokens, security violation

  The unconfirmed path dispatches a `user_confirmed` domain event as a
  fire-and-forget side effect through the global (non-sandboxed) DomainEventBus.
  That dispatch cannot be captured deterministically in a unit test, so we assert
  the observable state change the event announces — `confirmed_at` is set and the
  user's tokens are cleaned up — mirroring how the sibling context tests
  (AnonymizeUser, RegisterUser) assert outcomes rather than the dispatch itself.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures

  alias KlassHero.Accounts

  describe "login_user_by_magic_link/1 — confirmed user" do
    test "returns {:ok, {user, []}} for a valid token" do
      user = user_fixture()
      {token, _raw} = generate_user_magic_link_token(user)

      assert {:ok, {returned_user, []}} = Accounts.login_user_by_magic_link(token)
      assert returned_user.id == user.id
    end

    test "consumes the token — re-using it returns :not_found" do
      user = user_fixture()
      {token, _raw} = generate_user_magic_link_token(user)

      {:ok, _} = Accounts.login_user_by_magic_link(token)

      assert {:error, :not_found} = Accounts.login_user_by_magic_link(token)
    end
  end

  describe "login_user_by_magic_link/1 — unconfirmed user (no password)" do
    test "confirms the email and returns the now-confirmed user" do
      user = unconfirmed_user_fixture()
      assert is_nil(user.confirmed_at)

      {token, _raw} = generate_user_magic_link_token(user)

      assert {:ok, {confirmed_user, _expired_tokens}} = Accounts.login_user_by_magic_link(token)
      assert confirmed_user.id == user.id
      assert %DateTime{} = confirmed_user.confirmed_at
    end

    test "returns the expired tokens that were cleaned up" do
      user = unconfirmed_user_fixture()
      {token, _raw} = generate_user_magic_link_token(user)

      assert {:ok, {_user, expired_tokens}} = Accounts.login_user_by_magic_link(token)

      # Confirmation expires the consumed login token, so the cleanup list is
      # non-empty — distinguishing this path from the confirmed-user path above.
      refute expired_tokens == []
    end

    test "deletes all of the user's tokens after confirmation" do
      user = unconfirmed_user_fixture()
      {token, _raw} = generate_user_magic_link_token(user)
      {token2, _raw2} = generate_user_magic_link_token(user)

      {:ok, _} = Accounts.login_user_by_magic_link(token)

      assert {:error, :not_found} = Accounts.login_user_by_magic_link(token)
      assert {:error, :not_found} = Accounts.login_user_by_magic_link(token2)
    end
  end

  describe "login_user_by_magic_link/1 — error cases" do
    test "returns {:error, :invalid_token} for a malformed token" do
      assert {:error, :invalid_token} = Accounts.login_user_by_magic_link("not-a-valid!token@#$")
    end

    test "returns {:error, :not_found} for a well-formed but nonexistent token" do
      fake_token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
      assert {:error, :not_found} = Accounts.login_user_by_magic_link(fake_token)
    end

    test "returns {:error, :not_found} for an expired token" do
      user = user_fixture()
      {token, raw_token} = generate_user_magic_link_token(user)

      offset_user_token(raw_token, -20, :minute)

      assert {:error, :not_found} = Accounts.login_user_by_magic_link(token)
    end

    test "returns {:error, :security_violation} for an unconfirmed user with a password" do
      user = unconfirmed_user_fixture()
      user = set_password(user)
      {token, _raw} = generate_user_magic_link_token(user)

      assert {:error, :security_violation} = Accounts.login_user_by_magic_link(token)
    end
  end
end
