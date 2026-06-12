defmodule KlassHeroWeb.Router do
  use KlassHeroWeb, :router

  import Backpex.Router
  import KlassHeroWeb.UserAuth
  import Oban.Web.Router

  alias KlassHero.Shared.Tracing.LiveViewHook
  alias KlassHeroWeb.Hooks.RestoreLocale
  alias KlassHeroWeb.Plugs.SetLocale
  alias KlassHeroWeb.Plugs.VerifyWebhookSignature
  alias Plug.Swoosh.MailboxPreview

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug KlassHero.Shared.Tracing.Plug
    plug :fetch_live_flash
    plug :put_root_layout, html: {KlassHeroWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
    plug :set_error_tracker_context
    plug SetLocale
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :webhook do
    plug VerifyWebhookSignature
  end

  scope "/webhooks", KlassHeroWeb do
    pipe_through [:api, :webhook]

    post "/resend", ResendWebhookController, :handle
  end

  # Trigger: ThemeSelectorPlug reads session["backpex"]["theme"] for @theme assign
  # Why: only Backpex layout templates use @theme; non-admin routes don't need it
  # Outcome: avoids unnecessary session reads on every public/parent/provider request
  pipeline :backpex_admin do
    plug Backpex.ThemeSelectorPlug
  end

  # Health check endpoint for Fly.io
  scope "/", KlassHeroWeb do
    pipe_through :api

    get "/health", HealthController, :index
  end

  scope "/", KlassHeroWeb do
    pipe_through :browser

    # All public marketing routes — sticky horizontal mk_header + dark mk_footer chrome.
    live_session :marketing,
      layout: {KlassHeroWeb.Layouts, :marketing},
      on_mount: [
        {LiveViewHook, :trace},
        {KlassHeroWeb.UserAuth, :mount_current_scope},
        {RestoreLocale, :restore_locale}
      ] do
      live "/", HomeLive, :index
      live "/programs", ProgramsLive, :index
      live "/programs/:id", ProgramDetailLive, :show
      live "/trust-safety", TrustSafetyLive, :index
      live "/about", AboutLive, :index
      live "/contact", ContactLive, :index
      live "/for-providers", ForProvidersLive, :index
      live "/privacy", PrivacyPolicyLive, :index
      live "/terms", TermsOfServiceLive, :index
    end

    # Parent app surface — sidebar layout, parent-role required.
    # Layout swap (:app → :parent_app) is Phase 2 of the design-handoff
    # migration. /family/settings duplicates /settings under the bundle's
    # canonical parent path; both keep working until a follow-up adds a
    # 301 redirect for the legacy /settings tree.
    live_session :authenticated,
      layout: {KlassHeroWeb.Layouts, :parent_app},
      on_mount: [
        {LiveViewHook, :trace},
        {KlassHeroWeb.UserAuth, :require_authenticated},
        {KlassHeroWeb.UserAuth, :redirect_provider_or_staff_from_parent_routes},
        {KlassHeroWeb.UserAuth, :fetch_unread_count},
        {RestoreLocale, :restore_locale}
      ] do
      live "/dashboard", DashboardLive, :index

      live "/settings", SettingsLive, :index
      live "/settings/children", Settings.ChildrenLive, :index
      live "/settings/children/new", Settings.ChildrenLive, :new
      live "/settings/children/:child_id/edit", Settings.ChildrenLive, :edit

      # Bundle's canonical paths (Q2.4 — locked to dual-mount for v1).
      live "/family/settings", SettingsLive, :index
      live "/family/settings/children", Settings.ChildrenLive, :index
      live "/family/settings/children/new", Settings.ChildrenLive, :new
      live "/family/settings/children/:child_id/edit", Settings.ChildrenLive, :edit

      live "/programs/:id/booking", BookingLive, :new
      live "/messages", MessagesLive.Index, :index
      live "/messages/:id", MessagesLive.Show, :show
    end

    # Provider routes - provider role required.
    # Layout swap (:app → :provider_app) is Phase 3 of the design-handoff
    # migration. Black sidebar + yellow active accent across all
    # /provider/* surfaces.
    live_session :require_provider,
      layout: {KlassHeroWeb.Layouts, :provider_app},
      on_mount: [
        {LiveViewHook, :trace},
        {KlassHeroWeb.UserAuth, :require_authenticated},
        {KlassHeroWeb.UserAuth, :require_provider},
        {KlassHeroWeb.UserAuth, :fetch_unread_count},
        {RestoreLocale, :restore_locale}
      ] do
      scope "/provider", Provider do
        live "/sessions", SessionsLive, :index
        live "/sessions/new", SessionsLive, :new
        live "/participation/:session_id", ParticipationLive, :show

        live "/complete-profile", ProfileCompletionLive, :complete

        live "/incidents/new", IncidentReportLive, :new
        live "/programs/:program_id/incidents", IncidentReportsLive, :index

        # Provider dashboard routes
        live "/dashboard", DashboardLive, :overview
        live "/dashboard/team", DashboardLive, :team
        live "/dashboard/programs", DashboardLive, :programs
        live "/dashboard/edit", DashboardLive, :edit

        # Provider messaging routes
        live "/messages", MessagesLive.Index, :index
        live "/messages/:id", MessagesLive.Show, :show
        live "/programs/:program_id/broadcast", BroadcastLive, :new
      end
    end

    # Parent routes - parent role required (strict require_parent guard)
    live_session :require_parent,
      layout: {KlassHeroWeb.Layouts, :parent_app},
      on_mount: [
        {LiveViewHook, :trace},
        {KlassHeroWeb.UserAuth, :require_authenticated},
        {KlassHeroWeb.UserAuth, :require_parent},
        {KlassHeroWeb.UserAuth, :fetch_unread_count},
        {RestoreLocale, :restore_locale}
      ] do
      scope "/parent", Parent do
        live "/participation", ParticipationHistoryLive, :index
      end

      # Bundle's canonical /participation path (no /parent prefix). Same
      # LiveView; old /parent/participation kept as alias.
      scope "/", Parent do
        live "/participation", ParticipationHistoryLive, :index
      end
    end

    # Staff routes - :staff role required.
    # Q3.1 locked: staff surface uses the same provider_app layout for
    # visual consistency; bundle doesn't ship a separate staff design.
    live_session :require_staff,
      layout: {KlassHeroWeb.Layouts, :provider_app},
      on_mount: [
        {LiveViewHook, :trace},
        {KlassHeroWeb.UserAuth, :require_authenticated},
        {KlassHeroWeb.UserAuth, :require_staff},
        {KlassHeroWeb.UserAuth, :fetch_unread_count},
        {RestoreLocale, :restore_locale}
      ] do
      scope "/staff", Staff do
        live "/dashboard", StaffDashboardLive, :index
        live "/sessions", StaffSessionsLive, :index
        live "/participation/:session_id", StaffParticipationLive, :show
        live "/messages", MessagesLive.Index, :index
        live "/messages/:id", MessagesLive.Show, :show
        live "/programs/:program_id/broadcast", StaffBroadcastLive, :new
      end
    end

    # Admin routes - admin role required
    live_session :require_admin,
      layout: {KlassHeroWeb.Layouts, :app},
      on_mount: [
        {LiveViewHook, :trace},
        {KlassHeroWeb.UserAuth, :require_authenticated},
        {KlassHeroWeb.UserAuth, :require_admin},
        {RestoreLocale, :restore_locale}
      ] do
      scope "/admin", Admin do
        live "/verifications", VerificationsLive, :index
        live "/verifications/:id", VerificationsLive, :show
      end
    end

    # Backpex admin dashboard - separate live_session with Backpex layout
    scope "/admin", Admin do
      pipe_through :backpex_admin

      backpex_routes()

      # Trigger: no layout set on live_session for Backpex routes
      # Why: Backpex resource templates internally call <.layout> which renders
      #   the admin layout. Setting layout here would cause double-rendering
      #   and duplicate DOM IDs (backpex-app-shell).
      # Outcome: admin layout rendered once by Backpex, no duplicates
      live_session :backpex_admin,
        on_mount: [
          {LiveViewHook, :trace},
          {KlassHeroWeb.UserAuth, :require_authenticated},
          {KlassHeroWeb.UserAuth, :require_admin},
          {RestoreLocale, :restore_locale},
          Backpex.InitAssigns
        ] do
        live_resources("/accounts", AccountLive, only: [:index, :show, :edit])
        live_resources("/providers", ProviderLive, only: [:index, :show, :edit])
        live_resources("/staff", StaffLive, only: [:index, :show, :edit])
        live_resources("/bookings", BookingLive, only: [:index, :show])
        live_resources("/consents", ConsentLive, only: [:index, :show])
      end
    end

    # Custom admin LiveViews — separate live_session from Backpex
    scope "/admin", Admin do
      live_session :admin_custom,
        layout: {KlassHeroWeb.Layouts, :admin},
        on_mount: [
          {LiveViewHook, :trace},
          {KlassHeroWeb.UserAuth, :require_authenticated},
          {KlassHeroWeb.UserAuth, :require_admin},
          {RestoreLocale, :restore_locale}
        ] do
        live "/sessions", SessionsLive, :index
        live "/sessions/:id", SessionsLive, :show

        live "/emails", EmailsLive, :index
        live "/emails/:id", EmailsLive, :show
      end
    end
  end

  # Oban Web dashboard - admin only
  scope "/" do
    pipe_through :browser

    oban_dashboard("/oban",
      on_mount: [
        {KlassHeroWeb.UserAuth, :require_authenticated},
        {KlassHeroWeb.UserAuth, :require_admin}
      ]
    )
  end

  # Other scopes may use custom stacks.
  # scope "/api", KlassHeroWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:klass_hero, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: KlassHeroWeb.Telemetry
      forward "/mailbox", MailboxPreview
    end
  end

  ## Authentication routes
  ## Will be added by mix phx.gen.auth

  ## Authentication routes

  scope "/", KlassHeroWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      layout: {KlassHeroWeb.Layouts, :marketing},
      on_mount: [
        {LiveViewHook, :trace},
        {KlassHeroWeb.UserAuth, :require_authenticated},
        {KlassHeroWeb.UserAuth, :fetch_unread_count},
        {RestoreLocale, :restore_locale}
      ] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
    get "/users/export-data", UserDataExportController, :export
  end

  scope "/provider", KlassHeroWeb.Provider do
    pipe_through [:browser, :require_authenticated_user]

    post "/enrollment/import", EnrollmentImportController, :create
  end

  scope "/", KlassHeroWeb do
    pipe_through [:browser]

    get "/invites/:token", InviteClaimController, :show

    live_session :current_user,
      layout: {KlassHeroWeb.Layouts, :marketing},
      on_mount: [
        {LiveViewHook, :trace},
        {KlassHeroWeb.UserAuth, :mount_current_scope},
        {RestoreLocale, :restore_locale}
      ] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
      live "/users/staff-invitation/:token", UserLive.StaffInvitation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end

  if Application.compile_env(:klass_hero, :dev_routes) do
    use ErrorTracker.Web, :router

    scope "/dev" do
      pipe_through :browser

      error_tracker_dashboard "/errors"
    end
  end

  defp set_error_tracker_context(conn, _opts) do
    case conn.assigns[:current_scope] do
      %{user: %{id: id, email: email}} ->
        ErrorTracker.set_context(%{user_id: id, email: email})

      _ ->
        :ok
    end

    conn
  end
end
