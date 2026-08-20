defmodule KlassHero.Accounts.UserRolesTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias KlassHero.Accounts.UserRoles

  test "type/0 is an array of strings" do
    assert UserRoles.type() == {:array, :string}
  end

  describe "cast/1" do
    # {input, expected} — cast accepts atoms, strings, and a mix; dedups while
    # preserving first-seen order; treats nil/empty as the empty list.
    @valid [
      {[:parent], [:parent]},
      {["parent"], [:parent]},
      {[:parent, :provider], [:parent, :provider]},
      {["parent", "provider"], [:parent, :provider]},
      {[:parent, "provider"], [:parent, :provider]},
      {["parent", :provider], [:parent, :provider]},
      {[:parent, :parent], [:parent]},
      {["parent", "parent"], [:parent]},
      {[:parent, "parent"], [:parent]},
      {[:parent, :provider, :parent], [:parent, :provider]},
      {[:provider, :parent], [:provider, :parent]},
      {["provider", "parent"], [:provider, :parent]},
      {nil, []},
      {[], []}
    ]

    for {input, expected} <- @valid do
      @input input
      @expected expected
      test "casts #{inspect(input)} to #{inspect(expected)}" do
        assert UserRoles.cast(@input) == {:ok, @expected}
      end
    end

    @invalid [
      [:admin],
      [:parent, :admin],
      ["admin"],
      ["parent", "admin"],
      "parent",
      :parent,
      123,
      %{},
      [123],
      [nil],
      [:parent, 123]
    ]

    for input <- @invalid do
      @input input
      test "returns :error for #{inspect(input)}" do
        assert UserRoles.cast(@input) == :error
      end
    end
  end

  describe "load/1" do
    @valid [
      {["parent"], [:parent]},
      {["provider"], [:provider]},
      {["parent", "provider"], [:parent, :provider]},
      {["provider", "parent"], [:provider, :parent]},
      {nil, []},
      {[], []}
    ]

    for {input, expected} <- @valid do
      @input input
      @expected expected
      test "loads #{inspect(input)} to #{inspect(expected)}" do
        assert UserRoles.load(@input) == {:ok, @expected}
      end
    end

    @invalid [["admin"], ["parent", "admin"], [:parent], [123], [nil], "parent", :parent, 123]

    for input <- @invalid do
      @input input
      test "returns :error for #{inspect(input)}" do
        assert UserRoles.load(@input) == :error
      end
    end
  end

  describe "dump/1" do
    @valid [
      {[:parent], ["parent"]},
      {[:provider], ["provider"]},
      {[:parent, :provider], ["parent", "provider"]},
      {[:provider, :parent], ["provider", "parent"]},
      {nil, []},
      {[], []}
    ]

    for {input, expected} <- @valid do
      @input input
      @expected expected
      test "dumps #{inspect(input)} to #{inspect(expected)}" do
        assert UserRoles.dump(@input) == {:ok, @expected}
      end
    end

    @invalid [[:admin], [:parent, :admin], ["parent"], "parent", :parent, 123]

    for input <- @invalid do
      @input input
      test "returns :error for #{inspect(input)}" do
        assert UserRoles.dump(@input) == :error
      end
    end
  end

  test "embed_as/1 always dumps for event serialization" do
    for arg <- [:any, :self, :dump, nil] do
      assert UserRoles.embed_as(arg) == :dump
    end
  end

  property "cast → dump → load round-trips to the deduped atom roles" do
    check all(raw <- list_of(member_of(["parent", "provider"]), max_length: 5)) do
      expected = raw |> Enum.map(&String.to_existing_atom/1) |> Enum.uniq()

      {:ok, atoms} = UserRoles.cast(raw)
      {:ok, strings} = UserRoles.dump(atoms)
      {:ok, loaded} = UserRoles.load(strings)

      assert atoms == expected
      assert loaded == expected
    end
  end
end
