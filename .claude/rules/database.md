# Database

## Configuration

### Development Database

- PostgreSQL (default: user `postgres`, password `postgres`, host `localhost`, port `5432`)
- Database: `klass_hero_dev` on the main checkout; a worktree derives its own
  (`klass_hero_dev_<checkout>`) so migrations cannot escape into main's schema.
  Override either with `LOCAL_DEV_DATABASE`. See `.claude/rules/worktrees.md`.

### Test Database

- Docker-managed PostgreSQL container (isolated from development)
- Database: `klass_hero_test`
- Automatically managed by `mix test.setup` and `mix test.clean`

### Tidewave MCP Server

- Provides interactive Elixir REPL integration for development
- Access documentation, evaluate code, execute SQL queries
- Configured automatically when running `iex -S mix phx.server`

## Ecto Guidelines

- **Always** preload Ecto associations in queries when they'll be accessed in templates, ie a message that needs to reference the `message.user.email`
- Remember `import Ecto.Query` and other supporting modules when you write `seeds.exs`
- `Ecto.Schema` fields always use the `:string` type, even for `:text` columns, ie: `field :name, :string`
- `Ecto.Changeset.validate_number/2` **DOES NOT SUPPORT the `:allow_nil` option**. By default, Ecto validations only run if a change for the given field exists and the change value is not nil, so such an option is never needed
- You **must** use `Ecto.Changeset.get_field(changeset, :field)` to access changeset fields
- Fields which are set programmatically, such as `user_id`, must not be listed in `cast` calls or similar for security purposes. Instead they must be explicitly set when creating the struct

## Using Usage Rules for Docs

When looking for docs for modules & functions that are dependencies of the current project, or for Elixir itself, use `mix usage_rules.docs`:

```bash
# Search a whole module
mix usage_rules.docs Enum

# Search a specific function
mix usage_rules.docs Enum.zip

# Search a specific function & arity
mix usage_rules.docs Enum.zip/1
```

## Searching Documentation

Use the `usage_rules.search_docs` mix task for searching documentation:

```bash
# Search docs for all packages in the current application, including Elixir
mix usage_rules.search_docs Enum.zip

# Search docs for specific packages
mix usage_rules.search_docs Req.get -p req

# Search docs for multi-word queries
mix usage_rules.search_docs "making requests" -p req

# Search only in titles (useful for finding specific functions/modules)
mix usage_rules.search_docs "Enum.zip" --query-by title
```
