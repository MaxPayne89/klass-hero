defmodule KlassHeroWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :klass_hero

  alias KlassHeroWeb.Plugs.CacheRawBody
  alias Phoenix.Ecto.CheckRepoStatus
  alias Phoenix.Ecto.SQL.Sandbox
  alias Phoenix.LiveDashboard.RequestLogger
  alias Phoenix.LiveView.Socket

  @session_options [
    store: :cookie,
    key: "_klass_hero_key",
    signing_salt: "nKLK34NR",
    same_site: "Lax"
  ]

  socket "/live", Socket,
    websocket: [connect_info: [:user_agent, :x_headers, session: @session_options]],
    longpoll: [connect_info: [:user_agent, :x_headers, session: @session_options]]

  if Application.compile_env(:klass_hero, :sql_sandbox) do
    plug Sandbox
  end

  plug Plug.Static,
    at: "/",
    from: :klass_hero,
    gzip: not code_reloading?,
    only: KlassHeroWeb.static_paths()

  # Enable tidewave MCP
  if Code.ensure_loaded?(Tidewave) do
    plug Tidewave
  end

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug CheckRepoStatus, otp_app: :klass_hero
  end

  plug RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    body_reader: {CacheRawBody, :read_body, []},
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options

  plug KlassHeroWeb.Router
end
