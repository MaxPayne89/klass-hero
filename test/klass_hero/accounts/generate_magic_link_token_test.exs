defmodule KlassHero.Accounts.GenerateMagicLinkTokenTest do
  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures

  alias KlassHero.Accounts

  describe "generate_magic_link_token/1" do
    test "returns an encoded token string" do
      user = user_fixture()
      token = Accounts.generate_magic_link_token(user)
      assert {:ok, _} = Base.url_decode64(token, padding: false)
      assert byte_size(token) > 0
    end

    test "generated token can be verified" do
      user = user_fixture()
      token = Accounts.generate_magic_link_token(user)

      found_user = Accounts.get_user_by_magic_link_token(token)
      assert found_user.id == user.id
    end
  end
end
