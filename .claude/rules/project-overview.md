# Project Overview

Klass Hero is a website for afterschool activities, camps, and class trips management, connecting parents, instructors, and administrators.

## Tech Stack

- Backend: Elixir + Phoenix + PostgreSQL
- Frontend: Phoenix LiveView + HTML/CSS/JavaScript
- Database: PostgreSQL
- Infrastructure: Fly.io/Railway + GitHub Actions

## Project Structure

This is a Phoenix application with standard directory structure:

- `lib/klass_hero/` - Business logic and domain code
- `lib/klass_hero_web/` - Web layer (controllers, views, LiveView)
- `assets/` - CSS, JavaScript, and static assets
- `priv/` - Database migrations, seeds, and static files
- `test/` - Test files
- `config/` - Application configuration

## Development Commands

### Basic Commands

- `mix deps.get` - Install dependencies
- `mix ecto.create` - Create database
- `mix ecto.migrate` - Run database migrations
- `mix ecto.reset` - Drop, create, and migrate database
- `mix phx.server` - Start development server
- `iex -S mix phx.server` - Start server with interactive console

### Testing Commands

- `mix test` - Run all tests
- `mix test test/path/to/test.exs` - Run specific test file
- `mix test --failed` - Run only previously failed tests
- `mix test.setup` - Set up Docker test database
- `mix test.clean` - Clean test database (removes volumes and recreates)
- `mix test.db.setup` - Set up test database schema
- `mix precommit` - Run full pre-commit checks (compile with warnings as errors, format, test)

### Asset Commands

- `mix assets.setup` - Install Tailwind and esbuild
- `mix assets.build` - Compile CSS and JavaScript
- `mix assets.deploy` - Build and minify assets for production

### Complete Setup

- `mix setup` - Complete setup (deps, database, assets) in one command

## Development Status

**Current State:** Bounded contexts in conventional Phoenix (flattened from DDD/Ports & Adapters, #986–#1002)

- Authentication via `phx.gen.auth` with scope-based pattern
- Core LiveView pages (Home, Programs, Program Detail, Booking, Dashboard, Settings)
- Reusable component library organized by domain
- Mobile-first responsive design with Tailwind CSS
- Bounded contexts implemented: Accounts, Family, Provider, Program Catalog, Enrollment, Messaging, Participation, Entitlements, Shared
- Internationalization (English + German via Gettext)
