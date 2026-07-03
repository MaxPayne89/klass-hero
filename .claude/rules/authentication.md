# Authentication System

The project uses **Phoenix's standard `phx.gen.auth` authentication** for simplicity and maintainability. This provides a secure, well-tested authentication system (~500 lines) compared to the previous custom DDD/Ports & Adapters implementation (~2,100 lines).

## Directory Structure

Accounts is conventional Phoenix (flattened from DDD, #993):

```
lib/klass_hero/accounts/
  user.ex              # Schema-as-struct: Ecto schema + struct + functional core
  user_token.ex        # Token generation/verification
  scope.ex             # Accounts.Scope (auth scope)
  persona_grant.ex     # Role/persona grants
  user_notifier.ex     # Email sending utility
  types/               # user_role.ex, user_roles.ex (Ecto.Enum types)
  domain/events/       # user_events.ex, accounts_integration_events.ex

lib/klass_hero_web/
  user_auth.ex         # Authentication plug and helpers
  live/user_live/      # Authentication LiveView pages
    registration.ex    # User registration
    login.ex           # User login
    settings.ex        # User settings
    confirmation.ex    # Email confirmation
```

## Authentication Features

### Password + Email Confirmation Authentication

- Email confirmation required before account activation
- Secure token-based email verification
- Session token management with automatic cleanup
- Remember me functionality (60-day persistent sessions)
- Email change confirmation flow

### Security Features

- Bcrypt password hashing
- CSRF protection
- Session security with automatic cleanup
- Token expiration (confirmed within 1 day)
- Rate limiting on sensitive operations

## Scope-Based Authentication

The system uses an **Accounts.Scope** pattern for flexible authentication:

- **Assign**: `@current_scope` (NOT `@current_user`)
- **Access user**: `@current_scope.user`
- **Context functions**: Pass `current_scope` as first argument when needed

### Router Setup

```elixir
# Public routes (no auth required)
live_session :public do
  live "/", HomeLive, :index
end

# Routes with optional authentication
live_session :current_user,
  on_mount: [{KlassHeroWeb.UserAuth, :mount_current_scope}] do
  live "/users/register", UserLive.Registration, :new
end

# Routes requiring authentication
live_session :require_authenticated_user,
  on_mount: [{KlassHeroWeb.UserAuth, :require_authenticated}] do
  live "/dashboard", DashboardLive, :index
end
```

## User Authentication Pages

- `/users/register` - User registration
- `/users/log-in` - Login page
- `/users/log-in/:token` - Email confirmation
- `/users/settings` - User settings (requires auth)
- `/users/settings/confirm-email/:token` - Email change confirmation

## Layout Pattern

The application supports two Phoenix layout patterns in `app.html.heex`:

### Pattern 1: `live_session` layouts (custom app pages)

- Routes configured with `layout: {KlassHeroWeb.Layouts, :app}`
- Layout receives `@inner_content` assign from Phoenix
- Used by: Home, Programs, Dashboard, etc.

### Pattern 2: Component wrapper (generated auth pages)

- Generated auth LiveViews manually use `<Layouts.app>` component
- Layout receives `@inner_block` slot from component usage
- Used by: Registration, Login, Settings, etc.

### Implementation (lib/klass_hero_web/components/layouts/app.html.heex:219-225)

```heex
<main class="flex-1 relative z-0">
  <.flash_group flash={@flash} />
  <%= if assigns[:inner_content] do %>
    {@inner_content}
  <% else %>
    <%= render_slot(@inner_block) %>
  <% end %>
</main>
```

This conditional logic enables the same layout to work as both a `live_session` layout and a function component wrapper.

## Scope Configuration

**config/config.exs:**

```elixir
config :klass_hero, :scopes,
  user: [
    default: true,
    module: KlassHero.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: KlassHero.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]
```

This configuration enables the scope pattern for authentication, providing a flexible approach for future multi-tenant capabilities.
