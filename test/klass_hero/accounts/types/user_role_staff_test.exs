defmodule KlassHero.Accounts.Types.UserRoleStaffTest do
  use ExUnit.Case, async: true

  alias KlassHero.Accounts.Types.UserRole

  test ":staff is a valid role" do
    assert UserRole.valid_role?(:staff)
  end

  test ":staff can be converted to string" do
    assert {:ok, "staff"} = UserRole.to_string(:staff)
  end

  test ":staff can be parsed from string" do
    assert {:ok, :staff} = UserRole.from_string("staff")
  end

  test ":staff has permissions" do
    assert is_list(UserRole.permissions(:staff))
    refute Enum.empty?(UserRole.permissions(:staff))
  end
end
