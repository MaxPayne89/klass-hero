---
name: gen-migration
description: >-
  Scaffold a new database-backed entity in conventional Phoenix (schema-as-struct).
  Generates an Ecto migration and ONE entity module (Ecto schema + struct +
  functional core) at the context root, a test, and wires CRUD into the context
  facade. Invoke with:
  /gen-migration <context> <entity> [field:type ...] [--references table:field]
  Example: /gen-migration messaging reaction message_id:binary_id emoji:string --references messages:message_id
---

# Gen-Migration

Scaffold a database-backed entity following the project's **conventional Phoenix**
(schema-as-struct) convention. The contexts were flattened from DDD/Ports & Adapters
(#986–#1002): there are no domain-model structs, mappers, repository ports, or DI
wiring anymore. A new entity is ONE module at the context root.

**Type:** Rigid workflow. Follow steps exactly.

**Reference before generating:** read an existing table-backed entity in the same
context (canonical: `lib/klass_hero/provider/staff_member.ex`) and match its shape.

---

## Step 1: Parse Arguments

Extract from `$ARGUMENTS`:
- **context** (required): bounded context in snake_case (`messaging`, `enrollment`, `provider`)
- **entity** (required): entity name in snake_case (`reaction`, `program_review`)
- **fields** (optional): space-separated `name:type` pairs
- **--references** (optional): space-separated `table:field` pairs for foreign keys

Validate:
1. Context must exist under `lib/klass_hero/` — check the directory exists
2. Entity name must be snake_case
3. Field types must be valid Ecto types: `:string`, `:text`, `:integer`, `:boolean`,
   `:decimal`, `:binary_id`, `:utc_datetime`, `:utc_datetime_usec`, `:date`, `:map`,
   `{:array, :string}`, or an `Ecto.Enum` (see Step 3)

If no fields are provided, ask the user to describe the entity's fields.

## Step 2: Derive Names

| Concept | Derivation | Example (context=messaging, entity=reaction) |
|---------|-----------|-----------------------------------------------|
| Table name | Pluralized snake_case | `reactions` |
| Entity module | `KlassHero.{Context}.{Module}` | `KlassHero.Messaging.Reaction` |
| Entity file | `lib/klass_hero/{context}/{entity}.ex` | `lib/klass_hero/messaging/reaction.ex` |
| Context facade | `lib/klass_hero/{context}.ex` | `lib/klass_hero/messaging.ex` |
| Test file | `test/klass_hero/{context}/{entity}_test.exs` | `test/klass_hero/messaging/reaction_test.exs` |

There is NO separate domain model, schema, mapper, repository, port, or config key.

Present the derived names to the user for confirmation before generating.

## Step 3: Generate Migration

**File:** `priv/repo/migrations/{timestamp}_create_{table_name}.exs`

Generate timestamp: `date -u +"%Y%m%d%H%M%S"`

```elixir
defmodule KlassHero.Repo.Migrations.Create{PluralizedPascal} do
  use Ecto.Migration

  def change do
    create table(:{table_name}, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # For each reference field:
      add :{field}, references(:{table}, type: :binary_id, on_delete: :delete_all),
        null: false

      # For each regular field:
      add :{field}, :{type}, null: false  # or nullable if optional

      timestamps(type: :utc_datetime_usec)
    end

    # Index on every foreign key column
    create index(:{table_name}, [:{fk_field}])
    # Unique indexes if specified
  end
end
```

**Conventions:**
- `primary_key: false` on table, manual `:id` with `:binary_id`
- `timestamps(type: :utc_datetime_usec)` — microsecond precision on all new tables
- All references use `type: :binary_id` and `on_delete: :delete_all`
- `null: false` on required fields; explicit `create index` on every foreign key

## Step 4: Generate the Entity (schema-as-struct)

**File:** `lib/klass_hero/{context}/{entity}.ex`

This ONE module is the Ecto schema, the struct callers pattern-match on, and the
functional core.

```elixir
defmodule KlassHero.{Context}.{Module} do
  @moduledoc """
  {Entity description} (`{table_name}` table).

  Schema-as-struct: this module is both the Ecto schema and the struct consumers
  pattern-match on. Changesets are the validation gatekeeper at the DB boundary;
  pure business logic (validators, predicates) lives here too.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "{table_name}" do
    # Reference fields as :binary_id (or belongs_to when preloading is needed)
    field :{fk_field}, :binary_id

    # Regular fields
    field :{field}, :{type}
    # Enum fields: field :status, Ecto.Enum, values: [:pending, :active]

    timestamps()
  end

  @required_fields ~w({required_field_names})a
  @optional_fields ~w({optional_field_names})a

  @doc "Changeset for creating a {entity}."
  def create_changeset(%__MODULE__{} = {entity} \\ %__MODULE__{}, attrs) do
    {entity}
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:{fk_field})
  end

  @doc "Changeset for updating a {entity}."
  def update_changeset(%__MODULE__{} = {entity}, attrs) do
    {entity}
    |> cast(attrs, @optional_fields)
    |> validate_required(@required_fields)
  end

  # --- functional core: pure predicates / validators go here ---
  # e.g. def active?(%__MODULE__{status: :active}), do: true
end
```

**Conventions:**
- `@primary_key {:id, :binary_id, autogenerate: true}`, `@foreign_key_type :binary_id`,
  `@timestamps_opts [type: :utc_datetime_usec]`
- Programmatically-set fields (like `user_id`) must NOT be in `cast` — set via
  `put_change`/on struct creation (security: never cast server-controlled fields)
- `@required_fields` / `@optional_fields` module attributes; named changeset functions
- Pure business logic (predicates, state machines returning `{:error, [msg]}`) in the
  same module — no separate domain model
- NO mapper, NO repository, NO port, NO DI wiring

## Step 5: Wire CRUD into the Context Facade

**File:** `lib/klass_hero/{context}.ex`

The context module is the public data-access API and calls `Repo` directly. Add
functions mirroring the existing style in that facade:

```elixir
alias KlassHero.{Context}.{Module}
alias KlassHero.Repo

def create_{entity}(attrs) do
  %{Module}{}
  |> {Module}.create_changeset(attrs)
  |> Repo.insert()
end

def get_{entity}(id), do: Repo.get({Module}, id)
```

Match the surrounding facade's return-tuple and naming conventions. If the context
uses `application/commands|queries/` modules for orchestration, put multi-step
operations there and keep simple CRUD on the facade.

## Step 6: Generate a Test

**File:** `test/klass_hero/{context}/{entity}_test.exs`

Use `KlassHero.DataCase`. Cover: `create_changeset/2` validation (required fields,
FK constraint), and any functional-core predicate. Follow the `exunit-testing` skill.

## Step 7: Present Summary and Confirm

Before creating any files, present:

```
## Gen-Migration Plan

### Entity: {Module} in {Context}

### Files to create:
1. priv/repo/migrations/{timestamp}_create_{table_name}.exs
2. lib/klass_hero/{context}/{entity}.ex        # schema-as-struct
3. test/klass_hero/{context}/{entity}_test.exs

### Files to modify:
4. lib/klass_hero/{context}.ex                 # add CRUD facade functions

### Table: {table_name}
| Column | Type | Constraints |
|--------|------|-------------|
| id | binary_id | primary key |
| ... | ... | ... |
| inserted_at / updated_at | utc_datetime_usec | not null |

### Indexes: {index list}
```

**Wait for user confirmation before creating files.**

## Step 8: Generate All Files, then Verify

Create the migration, entity module, test, and facade edit. Then run:
```bash
mix format
mix compile --warnings-as-errors
mix test test/klass_hero/{context}/{entity}_test.exs
```
Diagnose and fix any failure before proceeding.

## Step 9: Run Migration

Ask the user if they want to run it now: `mix ecto.migrate`

---

## Rules

- **Never generate without confirmation.** Present the full plan in Step 7 first.
- **Read a similar entity in the same context as reference** (e.g. `provider/staff_member.ex`). Match its patterns.
- **One module per entity** — Ecto schema + struct + functional core together. No domain model, mapper, repository, port, or DI wiring.
- **The context facade calls `Repo` directly** — that is the data-access API now.
- **Binary UUIDs everywhere.** All IDs are `:binary_id`.
- **utc_datetime_usec for timestamps.** In migration and `@timestamps_opts`.
- **primary_key: false on tables.** Manual `:id` field with `:binary_id`.
- **Indexes on all foreign keys.** Every `references()` column gets an explicit index.
- **Never cast server-controlled fields** (`user_id`, etc.) — set them explicitly.
- **Run `mix compile --warnings-as-errors` after generation.** Zero warnings.
