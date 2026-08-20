# Context directories are flat, one level deep, and only when earned

A bounded context puts its modules **at the context root**. A kind of module gets its own
directory only once it holds **three or more files**, and that directory is one level deep:
`provider/projections/`, never `provider/adapters/driven/projections/`.

There is no `adapters/` layer, no `domain/` layer, and no `driven`/`driving` split.

```
context.ex
context/
├── <entity>.ex        <read_table>.ex     <use_case>.ex
├── events.ex          # factory for this context's integration events
├── <handler>.ex       # consumes another context's events
├── projections/  workers/  acl/  notifications/  queries/  read_models/
└──                    # each only once it holds 3+ files
```

## Why

The #986→#1002 flatten removed DDD's aggregate ports, mappers, and DI wiring, and dropped the
`boundary` library. It kept the directory scaffolding, sanctioned as a whitelist of survivors.
Three years of evidence say the scaffolding was the part worth deleting.

**The `driven`/`driving` split states directionality twice.** A handler or worker is inbound;
a projection, ACL, or notification is outbound. The kind name already says which. The extra
segment is not a second fact, it is the same fact re-encoded in the path — and it is a fact
nobody reads: the old rule of thumb ("if Oban triggers it, it's driving") was needed only to
decide which folder to type.

**The codebase already declared these segments meaningless.** `KlassHero.Shared.Tracing`
carries `@noise_segments` — a hardcoded list of module-name segments (`Adapters`, `Driven`,
`Driving`, `Persistence`, `Repositories`, `Schemas`, `Mappers`, `Queries`, `Events`,
`EventHandlers`, `Workers`, `Projections`) that `gen_span_name/1` strips back out before a
span is named, because a span called
`KlassHero.Provider.Adapters.Driven.Projections.ProviderPrograms.handle_event/2` is unreadable.
When the observability layer has to delete your directory structure to make traces legible,
the structure is noise. This ADR makes the file tree agree with what tracing already assumed.

**The cost is concrete and per-module.** Accounts paid four directory levels for one file,
`adapters/driving/events/staff_invitation_handler.ex`, yielding the seven-segment module name
`KlassHero.Accounts.Adapters.Driving.Events.StaffInvitationHandler`. Its event factory
stuttered: `Accounts.Domain.Events.AccountsEvents`.

**Nesting also hides drift.** Three test modules sat under
`test/klass_hero/accounts/adapters/driven/persistence/schemas/` — a path with no `lib`
counterpart since the original flatten deleted Accounts' driven side entirely. They tested
plain `User` changesets. A flat tree makes that kind of orphan obvious; a deep one absorbs it.

## The 3-file threshold

A directory earns its place when it saves you from scanning; below three files it only adds a
hop. This is the same extraction threshold the front end already applies to components
(`.claude/rules/frontend.md`), so it is one rule for the codebase rather than two.

It also means the convention scales in both directions. Accounts has nine modules and no
subdirectories at all. Provider has enough projections and workers that both keep a directory —
one level, holding files, rather than three levels holding one.

## Consequences

- Module names shorten by two to four segments. Span names do **not** change: the segments being
  removed are already in `@noise_segments`.
- `@noise_segments` becomes scaffolding for a tree that no longer exists — but it must survive
  until **every** context is flat, since it is load-bearing for the unconverted ones. Pruning it
  is the closing task of the last migration PR, not the first (#1259: a rename silently
  relocates production spans).
- Naming a module `<Context>.Events` puts a noise segment in the leaf position, so
  `gen_span_name/1` reduces it to bare `<Context>`. Harmless for a pure event factory, which
  emits no spans; do not give such a module tracing without renaming it first.
- ADR 0015 (`adapters/driven/acl/`) and ADR 0006 (Shared's `adapters/driven/persistence/`)
  describe paths in the pre-flat shape. Their **decisions** stand unchanged — only the spelling
  of the paths moves. Shared keeps its `adapters/` tree for now; its env-swapped seams are a
  separate question this ADR does not reopen.

## Migration

Accounts is the pilot and is flat. The remaining six contexts convert one PR at a time.

**Both shapes are legal until that completes.** Reviewers and review agents must accept either,
and must not flag an unconverted context — nor half-convert one as a drive-by, which produces a
context whose module names disagree with its own tree.

The lockstep rename sites for each remaining context are `lib/klass_hero/projection_supervisor.ex`
(which aliases projection modules by full name) and the alias block at the top of
`config/config.exs`. Both `mix lint_read_tables` and `mix lint_acl_boundary` are already
layout-agnostic — they check depth and first-path-segment respectively, never the literal
`adapters/driven` string — so neither needs changing.
