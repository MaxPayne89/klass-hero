defmodule KlassHero.Shared.Tracing.PlugTest do
  use ExUnit.Case, async: false
  use KlassHero.TracingHelpers

  import Plug.Conn
  import Plug.Test

  alias KlassHero.Shared.Tracing.Plug, as: TracingPlug

  # Span isolation (flush + drain between tests) is provided by the shared
  # `use KlassHero.TracingHelpers` setup.

  defp run_plug(conn) do
    opts = TracingPlug.init([])
    TracingPlug.call(conn, opts)
  end

  describe "creates root span for HTTP requests" do
    test "span name uses method and request path when no route pattern available" do
      _conn =
        conn(:get, "/programs")
        |> run_plug()
        |> send_resp(200, "OK")

      assert_span("HTTP GET /programs")
    end

    test "span name uses method and route pattern when available" do
      _conn =
        conn(:get, "/programs/123")
        |> put_private(:plug_route, {"/programs/:id", fn _ -> nil end})
        |> run_plug()
        |> send_resp(200, "OK")

      assert_span("HTTP GET /programs/:id")
    end

    test "sets http.method attribute" do
      _conn =
        conn(:post, "/programs")
        |> run_plug()
        |> send_resp(201, "Created")

      assert_span("HTTP POST /programs", "http.method": "POST")
    end

    test "sets http.target attribute to request path" do
      _conn =
        conn(:get, "/programs/abc")
        |> run_plug()
        |> send_resp(200, "OK")

      assert_span("HTTP GET /programs/abc", "http.target": "/programs/abc")
    end

    test "sets http.route attribute when route pattern is available" do
      _conn =
        conn(:get, "/programs/abc")
        |> put_private(:plug_route, {"/programs/:id", fn _ -> nil end})
        |> run_plug()
        |> send_resp(200, "OK")

      assert_span("HTTP GET /programs/:id", "http.route": "/programs/:id")
    end
  end

  describe "sets http.status_code on response" do
    test "records 200 status code" do
      _conn =
        conn(:get, "/programs")
        |> run_plug()
        |> send_resp(200, "OK")

      assert_span("HTTP GET /programs", "http.status_code": 200)
    end

    test "records 404 status code" do
      _conn =
        conn(:get, "/unknown")
        |> run_plug()
        |> send_resp(404, "Not Found")

      assert_span("HTTP GET /unknown", "http.status_code": 404)
    end
  end

  describe "sets error status for 5xx responses" do
    test "sets span status to error for 500" do
      _conn =
        conn(:get, "/programs")
        |> run_plug()
        |> send_resp(500, "Internal Server Error")

      http_span = assert_span("HTTP GET /programs")
      assert span_status_code(http_span) == :error
    end

    test "sets span status to error for 503" do
      _conn =
        conn(:get, "/programs")
        |> run_plug()
        |> send_resp(503, "Service Unavailable")

      http_span = assert_span("HTTP GET /programs")
      assert span_status_code(http_span) == :error
    end

    test "does not set error status for 4xx responses" do
      _conn =
        conn(:get, "/missing")
        |> run_plug()
        |> send_resp(404, "Not Found")

      http_span = assert_span("HTTP GET /missing")

      # When no error status is set, span(:status) returns :undefined (OTel default).
      # Only a span explicitly set to :error is a failure — :undefined and :ok are fine.
      raw_status = span(http_span, :status)
      assert raw_status == :undefined or span_status_code(http_span) != :error
    end
  end
end
