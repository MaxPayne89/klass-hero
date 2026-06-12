defmodule KlassHeroWeb.RoleRoutingTest do
  use ExUnit.Case, async: true

  alias KlassHeroWeb.RoleRouting

  describe "primary_role/1" do
    test "provider takes precedence over staff and parent" do
      assert RoleRouting.primary_role([:parent, :staff, :provider]) == :provider
    end

    test "staff takes precedence over parent" do
      assert RoleRouting.primary_role([:parent, :staff]) == :staff
    end

    test "parent when only parent present" do
      assert RoleRouting.primary_role([:parent]) == :parent
    end

    test "nil when no known role present" do
      assert RoleRouting.primary_role([]) == nil
    end
  end

  describe "dashboard_path/1" do
    test "provider dashboard wins for a provider+staff user" do
      assert RoleRouting.dashboard_path([:provider, :staff]) == "/provider/dashboard"
    end

    test "staff dashboard for a staff-only user" do
      assert RoleRouting.dashboard_path([:staff]) == "/staff/dashboard"
    end

    test "generic dashboard for parent or unknown" do
      assert RoleRouting.dashboard_path([:parent]) == "/dashboard"
      assert RoleRouting.dashboard_path([]) == "/dashboard"
    end
  end

  describe "messages_path/1" do
    test "provider messages wins for a provider+staff user" do
      assert RoleRouting.messages_path([:provider, :staff]) == "/provider/messages"
    end

    test "staff messages for a staff-only user" do
      assert RoleRouting.messages_path([:staff]) == "/staff/messages"
    end

    test "generic messages for parent or unknown" do
      assert RoleRouting.messages_path([:parent]) == "/messages"
      assert RoleRouting.messages_path([]) == "/messages"
    end
  end
end
