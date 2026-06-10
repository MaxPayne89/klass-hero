# Klass Hero

**Afterschool activities, camps, and class trips management platform** connecting parents, providers, and administrators.

## Tech Stack

- **Backend**: Elixir 1.20 + Phoenix Framework + PostgreSQL
- **Frontend**: Phoenix LiveView with Tailwind CSS
- **Infrastructure**: Fly.io/Railway + GitHub Actions

## Quick Start

### Prerequisites

Install the following on your system:

**1. asdf (version manager)**

Install asdf to manage Elixir and Erlang versions:

- **Mac**: `brew install asdf`
- **Linux**: Follow the [asdf installation guide](https://asdf-vm.com/guide/getting-started.html)

After installing, add asdf to your shell and install the required plugins:

```bash
# Add to shell (follow asdf docs for your specific shell)
# Then install plugins:
asdf plugin add erlang
asdf plugin add elixir
```

**2. Docker & Docker Compose**

- **Mac**: [Install Docker Desktop](https://docs.docker.com/desktop/install/mac-install/)
- **Linux**: [Install Docker Engine](https://docs.docker.com/engine/install/) + Docker Compose
- **Windows**: [Install Docker Desktop](https://docs.docker.com/desktop/install/windows-install/)

Verify installation:
```bash
docker --version
docker-compose --version
```

**3. Git**

Usually pre-installed. If needed:
- **Mac**: `brew install git`
- **Linux**: `sudo apt-get install git`

### Setup

**1. Clone and navigate:**

```bash
git clone https://github.com/YOUR_USERNAME/klass-hero.git
cd klass-hero
```

**2. Install Elixir and Erlang:**

```bash
# Install versions specified in .tool-versions
asdf install
```

This installs:
- Erlang 29.0.2
- Elixir 1.20.1-otp-29

**3. Start PostgreSQL:**

```bash
docker-compose up -d
```

This starts a PostgreSQL 18 container in the background.

**4. Run application setup:**

```bash
mix setup
```

This command:
- Installs dependencies
- Creates the database
- Runs migrations
- Builds assets (Tailwind CSS & esbuild)

**5. Start the development server:**

```bash
mix phx.server
```

**6. Open in browser:**

```text
http://localhost:4000
```

### What if setup fails?

Run commands individually to isolate the issue:

```bash
# Install Elixir/Erlang
asdf install

# Start database
docker-compose up -d

# Check database is running
docker-compose ps

# Install dependencies
mix deps.get

# Create database
mix ecto.create

# Run migrations
mix ecto.migrate

# Build assets
mix assets.setup
mix assets.build
```

## Version Management

This project uses asdf to ensure consistent Elixir/Erlang versions across development environments.

**Versions** (defined in `.tool-versions`):
- Erlang: 29.0.2
- Elixir: 1.20.1-otp-29
- PostgreSQL: 18 (Docker)

After cloning, run `asdf install` to automatically install the correct versions.

## Available Pages

**Public:**
- Homepage: `http://localhost:4000`
- Programs: `http://localhost:4000/programs`
- Login/Signup: `http://localhost:4000/users/log-in`

**Authenticated:**
- Dashboard: `http://localhost:4000/dashboard`
- Settings: `http://localhost:4000/users/settings`

**Development Tools:**
- Live Dashboard: `http://localhost:4000/dev/dashboard`
- Email Preview: `http://localhost:4000/dev/mailbox`

## Development

### Common Commands

```bash
# Database
mix ecto.reset              # Drop, create, and migrate
mix ecto.rollback           # Rollback last migration

# Testing
mix test                    # Run all tests
mix test --failed           # Run failed tests
mix precommit               # Full pre-commit checks

# Server
mix phx.server              # Start server
iex -S mix phx.server       # Start with interactive console
```

### Docker Management

**Start PostgreSQL:**
```bash
docker-compose up -d
```

**Stop PostgreSQL:**
```bash
docker-compose down
```

**View logs:**
```bash
docker-compose logs -f postgres
```

**Check status:**
```bash
docker-compose ps
```

**Reset database (removes all data):**
```bash
docker-compose down -v
docker-compose up -d
mix ecto.reset
```

### Making Changes

The app auto-reloads when files change. Edit and save:
- Code: `lib/klass_hero_web/`
- Styles: `assets/css/`

Stop the server with `Ctrl+C` twice.

## Testing

The test suite uses Docker-managed PostgreSQL for isolation.

**Run tests** (automatically starts Docker if needed):
```bash
mix test
```

**First-time setup:**
```bash
mix test.setup       # Starts Docker container
```

**Clean slate:**
```bash
mix test.clean       # Removes volumes and recreates container
```

**Before committing:**
```bash
mix precommit        # Compile, format, and test
```

The `mix test` command automatically:
1. Starts the Docker PostgreSQL container (if not running)
2. Creates the test database
3. Runs migrations
4. Executes the test suite

## Troubleshooting

### Docker Issues

**Container not starting:**
```bash
# Check Docker is running
docker ps

# Check container logs
docker-compose logs postgres

# Restart container
docker-compose restart
```

**Port 5432 already in use:**
```bash
# Find process using port 5432
lsof -i :5432

# Stop conflicting PostgreSQL instance
brew services stop postgresql  # Mac with Homebrew
sudo systemctl stop postgresql  # Linux
```

**Database connection refused:**
```bash
# Verify container is running
docker-compose ps

# Check container health
docker-compose exec postgres pg_isready -U postgres

# Restart container
docker-compose restart
```

### Common Errors

| Error | Fix |
|-------|-----|
| `docker: command not found` | Install Docker Desktop |
| `docker-compose: command not found` | Install Docker Compose or update Docker Desktop |
| `Cannot connect to the Docker daemon` | Start Docker Desktop |
| `port 5432 already in use` | Stop other PostgreSQL instances or change port in docker-compose.yml |
| `database already exists` | Run `mix ecto.reset` |
| `port 4000 already in use` | Kill process: `lsof -i :4000` then `kill -9 <PID>` |
| `asdf: command not found` | Install asdf and add to shell configuration |
| `No version set for elixir` | Run `asdf install` in project directory |

### Verifying Setup

**Check Elixir/Erlang versions:**
```bash
elixir --version
# Should show: Elixir 1.20.1 (compiled with Erlang/OTP 29)
```

**Check PostgreSQL:**
```bash
# Connect to database
docker-compose exec postgres psql -U postgres -d klass_hero_dev

# Inside psql, check version:
SELECT version();
# Should show PostgreSQL 18

# Exit with \q
```

**Check Docker container:**
```bash
docker-compose ps
# Should show klass_hero_postgres as "Up"
```

### Nuclear Reset

If nothing works, reset everything:

```bash
# Stop and remove Docker containers and volumes
docker-compose down -v

# Remove build artifacts
mix deps.clean --all
rm -rf _build

# Start fresh
docker-compose up -d
mix deps.get
mix setup
```

## Architecture

This project follows Domain-Driven Design with Ports & Adapters architecture. Key contexts:

- **Program Catalog** - Program discovery and details
- **Enrollment** - Enrollment process from selection to payment
- **Family Management** - Family data and relationships
- **Progress Tracking** - Child progress and achievements
- **Review & Rating** - Program reviews and feedback

**Documentation:**
- `.claude/rules/domain-architecture.md` - DDD patterns and key conventions

## Project Structure

```text
lib/
├── klass_hero/          # Business logic (contexts)
├── klass_hero_web/      # Web layer (LiveView, controllers)
assets/                   # CSS, JavaScript
priv/                     # Migrations, seeds, static files
test/                     # Test files
```
