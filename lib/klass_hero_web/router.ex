defmodule KlassHeroWeb.Router do
  use KlassHeroWeb, :router

  import Backpex.Router
  import KlassHeroWeb.UserAuth
  import Oban.Web.Router

  alias KlassHero.Shared.Tracing.LiveViewHook
  alias KlassHeroWeb.Hooks.RestoreLocale
  alias KlassHeroWeb.Plugs.SetLocale
  alias KlassHeroWeb.Plugs.VerifyStripeWebhookSignature
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

  # Stripe uses a distinct signature scheme (t=,v1= HMAC-SHA256), so it gets its own plug.
  pipeline :stripe_webhook do
    plug VerifyStripeWebhookSignature
  end

  scope "/webhooks", KlassHeroWeb do
    pipe_through [:api, :webhook]

    post "/resend", ResendWebhookController, :handle
  end

  scope "/webhooks", KlassHeroWeb do
    pipe_through [:api, :stripe_webhook]

    post "/stripe", StripeWebhookController, :handle
  end

  # Only Backpex layout templates use @theme; skip the session read on non-admin routes.
  pipeline :backpex_admin do
    plug Backpex.ThemeSelectorPlug
  end

  # /health is Fly.io's machine check; /health/ready is for external uptime monitoring.
  # See KlassHeroWeb.HealthController for why they must stay separate.
  scope "/", KlassHeroWeb do
    pipe_through :api

    get "/health", HealthController, :index
    get "/health/ready", HealthController, :ready
  end

  scope "/", KlassHeroWeb do
    pipe_through :browser

    # Language changes go through the plug pipeline because only it can write the
    # session, and only its redirect re-renders the root layout's <html lang>.
    get "/locale/:locale", LocaleController, :update

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

    # /family/settings dual-mounts /settings under the canonical parent path;
    # both work until a follow-up adds a 301 redirect for the legacy /settings tree.
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

      live "/family/settings", SettingsLive, :index
      live "/family/settings/children", Settings.ChildrenLive, :index
      live "/family/settings/children/new", Settings.ChildrenLive, :new
      live "/family/settings/children/:child_id/edit", Settings.ChildrenLive, :edit

      live "/programs/:id/booking", BookingLive, :new
      live "/messages", MessagesLive.Index, :index
      live "/messages/:id", MessagesLive.Show, :show
    end

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

        live "/verification", VerificationLive, :index

        live "/incidents/new", IncidentReportLive, :new
        live "/programs/:program_id/incidents", IncidentReportsLive, :index

        live "/dashboard", OverviewLive, :index
        live "/dashboard/team", TeamLive, :index
        live "/dashboard/programs", ProgramsLive, :index
        live "/dashboard/edit", EditProfileLive, :index

        live "/messages", MessagesLive.Index, :index
        live "/messages/:id", MessagesLive.Show, :show
        live "/programs/:program_id/broadcast", BroadcastLive, :new
      end
    end

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

      # /participation also mounted without /parent prefix; /parent/participation kept as alias.
      scope "/", Parent do
        live "/participation", ParticipationHistoryLive, :index
      end
    end

    # Staff uses provider_app layout for visual consistency; no separate staff design.
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

    scope "/admin", Admin do
      pipe_through :backpex_admin

      backpex_routes()

      # No layout set here — Backpex resource templates call <.layout> internally;
      # setting one would double-render and produce duplicate backpex-app-shell IDs.
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
        live_resources("/incidents", IncidentLive, only: [:index, :show])
      end
    end

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

  scope "/" do
    pipe_through :browser

    oban_dashboard("/oban",
      on_mount: [
        {KlassHeroWeb.UserAuth, :require_authenticated},
        {KlassHeroWeb.UserAuth, :require_admin}
      ]
    )
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:klass_hero, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: KlassHeroWeb.Telemetry
      forward "/mailbox", MailboxPreview
    end
  end

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
