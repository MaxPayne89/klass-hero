defmodule KlassHero.Accounts.UserRoleTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias KlassHero.Accounts.UserRole

  test "valid_roles/0 returns the known role atoms" do
    assert UserRole.valid_roles() == [:parent, :provider, :staff]
  end

  describe "valid_role?/1" do
    # {input, expected} — only the three known atoms are valid; strings and other
    # types are not.
    @cases [
      {:parent, true},
      {:provider, true},
      {:staff, true},
      {:admin, false},
      {:user, false},
      {:invalid, false},
      {"parent", false},
      {"provider", false},
      {nil, false},
      {123, false},
      {%{}, false},
      {[], false}
    ]

    for {input, expected} <- @cases do
      @input input
      @expected expected
      test "#{inspect(input)} -> #{expected}" do
        assert UserRole.valid_role?(@input) == @expected
      end
    end
  end

  describe "to_string/1" do
    @cases [
      {:parent, {:ok, "parent"}},
      {:provider, {:ok, "provider"}},
      {:staff, {:ok, "staff"}},
      {:admin, {:error, :invalid_role}},
      {:invalid, {:error, :invalid_role}},
      {"parent", {:error, :invalid_role}},
      {nil, {:error, :invalid_role}},
      {123, {:error, :invalid_role}}
    ]

    for {input, expected} <- @cases do
      @input input
      @expected expected
      test "#{inspect(input)} -> #{inspect(expected)}" do
        assert UserRole.to_string(@input) == @expected
      end
    end
  end

  describe "from_string/1" do
    @cases [
      {"parent", {:ok, :parent}},
      {"provider", {:ok, :provider}},
      {"staff", {:ok, :staff}},
      {"admin", {:error, :invalid_role}},
      {"user", {:error, :invalid_role}},
      {"invalid", {:error, :invalid_role}},
      {"", {:error, :invalid_role}},
      {:parent, {:error, :invalid_role}},
      {nil, {:error, :invalid_role}},
      {123, {:error, :invalid_role}},
      {%{}, {:error, :invalid_role}}
    ]

    for {input, expected} <- @cases do
      @input input
      @expected expected
      test "#{inspect(input)} -> #{inspect(expected)}" do
        assert UserRole.from_string(@input) == @expected
      end
    end

    test "prevents atom pollution by using to_existing_atom" do
      assert UserRole.from_string("nonexistent_role_xyz") == {:error, :invalid_role}

      assert_raise ArgumentError, fn ->
        String.to_existing_atom("nonexistent_role_xyz")
      end
    end
  end

  property "to_string then from_string round-trips every valid role" do
    check all(role <- member_of(UserRole.valid_roles())) do
      {:ok, string} = UserRole.to_string(role)
      assert UserRole.from_string(string) == {:ok, role}
    end
  end

  property "from_string rejects arbitrary strings without creating atoms" do
    check all(
            string <- string(:alphanumeric, min_length: 1),
            string not in ~w(parent provider staff)
          ) do
      assert UserRole.from_string(string) == {:error, :invalid_role}
    end
  end
end
