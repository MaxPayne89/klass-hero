defmodule KlassHeroWeb.Plugs.CacheRawBodyTest do
  use ExUnit.Case, async: true

  import Plug.Test, only: [conn: 3]

  alias KlassHero.Test.ErroringBodyAdapter
  alias KlassHeroWeb.Plugs.CacheRawBody

  describe "read_body/2" do
    test "returns the body and caches it in assigns" do
      conn = conn(:post, "/webhooks/stripe", ~s({"id":"evt_1"}))

      assert {:ok, ~s({"id":"evt_1"}), conn} = CacheRawBody.read_body(conn, [])
      assert conn.assigns.raw_body == ~s({"id":"evt_1"})
    end

    test "reassembles a body delivered across several chunks" do
      body = ~s({"id":"evt_1","type":"checkout.session.completed"})
      conn = conn(:post, "/webhooks/stripe", body)

      # `length: 1` forces Plug's test adapter down its {:more, _, _} path, so this
      # exercises the accumulator rather than the single-read happy path above.
      assert {:ok, ^body, conn} = CacheRawBody.read_body(conn, length: 1)
      assert conn.assigns.raw_body == body
    end

    test "propagates an error instead of raising when the client aborts immediately" do
      conn = %{conn(:post, "/webhooks/stripe", "") | adapter: {ErroringBodyAdapter, :error_now}}

      assert {:error, :timeout} = CacheRawBody.read_body(conn, [])
    end

    test "propagates an error instead of raising when the client aborts mid-body" do
      conn = %{
        conn(:post, "/webhooks/stripe", "")
        | adapter: {ErroringBodyAdapter, {:more_then_error, ~s({"id":)}}
      }

      assert {:error, :timeout} = CacheRawBody.read_body(conn, [])
    end
  end
end
