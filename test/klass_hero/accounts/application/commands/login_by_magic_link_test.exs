defmodule KlassHero.Accounts.Application.Commands.LoginByMagicLinkTest do
  @moduledoc """
  Tests for LoginByMagicLink.execute/1.

  Covers the three dispatch paths:
  1. Confirmed user    — deletes the specific token, returns the user
  2. Unconfirmed user  — confirms email, deletes all tokens, dispatches user_confirmed
  3. Error cases       — invalid/malformed/expired tokens, security violation
  """

  use KlassHero.DataCase, async: false

  import KlassHero.AccountsFixtures
  import KlassHero.EventTestHelper

  alias KlassHero.Accounts.Application.Commands.LoginByMagicLink
  alias KlassHero.Shared.Adapters.Driven.Events.TestEventPublisher
  alias KlassHero.Shared.DomainEventBus

  setup do
    setup_test_events()

    # LoginByMagicLink dispatches user_confirmed via DomainEventBus (fire-and-forget),
    # not through the TestEventPublisher port.  Bridge them so assert_event_published works.
    DomainEventBus.subscribe(KlassHero.Accounts, :user_confirmed, fn event ->
      TestEventPublisher.publish(event)
      :ok
    end)

    :ok
  end

  describe "execute/1 — confirmed user" do
    test "returns {:ok, {user, []}} for a valid token" do
      user = user_fixture()
      {token, _raw} = generate_user_magic_link_token(user)

      assert {:ok, {returned_user, []}} = LoginByMagicLink.execute(token)
      assert returned_user.id == user.id
    end

    test "token is consumed — re-using the same token returns :not_found" do
      user = user_fixture()
      {token, _raw} = generate_user_magic_link_token(user)

      {:ok, _} = LoginByMagicLink.execute(token)

      assert {:error, :not_found} = LoginByMagicLink.execute(token)
    end

    test "does not dispatch a user_confirmed event" do
      user = user_fixture()
      {token, _raw} = generate_user_magic_link_token(user)

      {:ok, _} = LoginByMagicLink.execute(token)

      assert TestEventPublisher.get_events() == []
    end
  end

  describe "execute/1 — unconfirmed user (no password)" do
    test "returns {:ok, {user, []}} and user has confirmed_at set" do
      user = unconfirmed_user_fixture()
      assert is_nil(user.confirmed_at)

      {token, _raw} = generate_user_magic_link_token(user)

      assert {:ok, {confirmed_user, []}} = LoginByMagicLink.execute(token)
      assert confirmed_user.id == user.id
      assert %DateTime{} = confirmed_user.confirmed_at
    end

    test "all tokens are deleted after confirmation" do
      user = unconfirmed_user_fixture()
      {token, _raw} = generate_user_magic_link_token(user)
      # Generate a second token to verify all tokens are cleaned up
      {token2, _raw2} = generate_user_magic_link_token(user)

      {:ok, _} = LoginByMagicLink.execute(token)

      # Both tokens should now be gone
      assert {:error, :not_found} = LoginByMagicLink.execute(token)
      assert {:error, :not_found} = LoginByMagicLink.execute(token2)
    end

    test "dispatches user_confirmed domain event" do
      user = unconfirmed_user_fixture()
      {token, _raw} = generate_user_magic_link_token(user)

      {:ok, {confirmed_user, []}} = LoginByMagicLink.execute(token)

      event = assert_event_published(:user_confirmed)
      assert event.aggregate_id == confirmed_user.id
    end
  end

  describe "execute/1 — error cases" do
    test "returns {:error, :invalid_token} for a malformed token" do
      assert {:error, :invalid_token} = LoginByMagicLink.execute("not-a-valid!token@#$")
    end

    test "returns {:error, :not_found} for a well-formed but nonexistent token" do
      fake_token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
      assert {:error, :not_found} = LoginByMagicLink.execute(fake_token)
    end

    test "returns {:error, :not_found} for an expired token" do
      user = user_fixture()
      {token, raw_token} = generate_user_magic_link_token(user)

      offset_user_token(raw_token, -20, :minute)

      assert {:error, :not_found} = LoginByMagicLink.execute(token)
    end

    test "returns {:error, :security_violation} for unconfirmed user with password" do
      user = unconfirmed_user_fixture()
      user = set_password(user)
      {token, _raw} = generate_user_magic_link_token(user)

      assert {:error, :security_violation} = LoginByMagicLink.execute(token)
    end
  end
end
