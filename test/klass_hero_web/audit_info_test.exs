defmodule KlassHeroWeb.AuditInfoTest do
  use ExUnit.Case, async: true

  alias KlassHeroWeb.AuditInfo

  describe "from_connect_info/1" do
    test "takes the client IP from fly-client-ip" do
      info = %{user_agent: "Mozilla/5.0", x_headers: [{"fly-client-ip", "203.0.113.7"}]}

      assert AuditInfo.from_connect_info(info) == %{
               ip_address: "203.0.113.7",
               user_agent: "Mozilla/5.0"
             }
    end

    test "ignores x-forwarded-for — it is client-spoofable" do
      info = %{user_agent: "Mozilla/5.0", x_headers: [{"x-forwarded-for", "198.51.100.1"}]}

      assert %{ip_address: nil} = AuditInfo.from_connect_info(info)
    end

    test "prefers fly-client-ip even when x-forwarded-for is also present" do
      info = %{
        user_agent: "Mozilla/5.0",
        x_headers: [{"x-forwarded-for", "198.51.100.1"}, {"fly-client-ip", "203.0.113.7"}]
      }

      assert %{ip_address: "203.0.113.7"} = AuditInfo.from_connect_info(info)
    end

    test "records nil rather than a placeholder when no trusted header is present" do
      assert AuditInfo.from_connect_info(%{user_agent: "Mozilla/5.0", x_headers: []}) == %{
               ip_address: nil,
               user_agent: "Mozilla/5.0"
             }
    end

    test "tolerates a nil connect_info — the dead render has none" do
      assert AuditInfo.from_connect_info(nil) == %{ip_address: nil, user_agent: nil}
    end

    test "tolerates missing keys" do
      assert AuditInfo.from_connect_info(%{}) == %{ip_address: nil, user_agent: nil}
    end

    test "matches the header name case-insensitively" do
      info = %{user_agent: nil, x_headers: [{"Fly-Client-IP", "203.0.113.7"}]}
      assert %{ip_address: "203.0.113.7"} = AuditInfo.from_connect_info(info)
    end
  end
end
