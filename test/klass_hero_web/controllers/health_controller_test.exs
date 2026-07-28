defmodule KlassHeroWeb.HealthControllerTest do
  use KlassHeroWeb.ConnCase, async: true

  describe "GET /health" do
    test "reports ok", %{conn: conn} do
      conn = get(conn, ~p"/health")

      assert json_response(conn, 200) == %{"status" => "ok"}
    end
  end

  describe "GET /health/ready" do
    test "reports ok when the database is reachable", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")

      assert json_response(conn, 200) == %{"status" => "ok"}
    end
  end
end
