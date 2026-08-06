# Cross-context reads call the owning context's facade directly

A bounded context that needs to read another context's data **calls that context's root facade
directly** — `KlassHero.Family.get_children_by_ids/1`, not an adapter that forwards to it. This
holds at every layer: a projection, an event handler, an Oban worker, a domain module and a web
helper all call the facade the same way, with nothing in between.

This settles a question the codebase had been answering two ways. The original DDD/Ports &
Adapters design routed every cross-context read through an anti-corruption layer under
`adapters/driven/acl/`, and that instruction survived the #986→#1002 flatten in prose even as
practice moved on (#1027, #1195, #1196). The result was twelve ACL modules of which five did no
translation at all, a rule nobody followed, and a review agent configured to flag the pattern we
had actually settled on.

## Why direct

An ACL is worth its indirection when it **translates**. Most of ours did not: they called one
facade function and returned its result, or narrowed a struct into a plain map whose keys were
the struct's own field names — so `details.gender` resolved identically with or without the
adapter. What that bought was a second module to find, a second place for the contract to drift,
and a test file asserting the shape of the narrowing rather than the behaviour underneath.

The isolation an ACL is supposed to provide is already provided by the facade. The facade *is*
the anti-corruption layer: it is the only public surface, it owns its return types, and ADR 0001's
"no SQL joins across context tables" makes it the only door. A pass-through adapter in front of a
facade guards a boundary that was never open.

## When an ACL still earns its place

Keep — or add — an ACL under `adapters/driven/acl/` when it does real work:

- **Business-rule masking.** `participation/…/child_info_resolver.ex` returns `allergies`,
  `support_needs` and `emergency_contact` only when `"provider_data_sharing"` consent is active.
  That rule belongs to Participation, not Family.
- **Error remapping into the caller's vocabulary.**
  `participation/…/program_provider_resolver.ex` turns an empty
  `ProgramCatalog.get_programs_by_ids/1` result into `:program_not_found`.
- **Cycle-breaking direct table access.** `enrollment/…/program_catalog_acl.ex` and
  `…/program_schedule_acl.ex` query `programs` directly because ProgramCatalog already depends on
  Enrollment for capacity; `family/…/child_enrollment_acl.ex` and `…/child_participation_acl.ex`
  do the same for cross-context *writes* during child deletion. Each says so in its moduledoc —
  that justification is a requirement, not a courtesy.
- **A query no facade expresses.** `provider/…/participation_session_stats_acl.ex` runs a
  multi-table join to bootstrap a projection.

An ACL whose every function forwards a call is not one of these. Fold it into its caller.

## Consequences

- **The default is the shortest path.** New cross-context reads call the facade; adding an ACL
  now requires naming which of the four justifications applies.
- **Observability is preserved at the call site, not by the adapter.** Where a folded ACL carried
  `acl_span source:/target:`, the direct call keeps it — `provider/assignments.ex:307` is the
  reference shape. Folding shifts the emitted spans in three ways, all of which a saved
  Honeycomb query could notice:

  1. **`acl.operation` is renamed.** The macro derives it from the enclosing function, so the
     value follows the new private helper rather than the deleted ACL function. The #1269 fold
     renamed five: `get_children_by_ids`→`fetch_children`, `get_parents_by_ids`→`fetch_parents`,
     `child_belongs_to_parent?`→`ensure_child_belongs_to_parent`,
     `resolve_identity_id`→`resolve_parent_id`, `get_participant_details`→`fetch_child`.
  2. **Span count can rise.** An ACL that short-circuited before its own `acl_span`
     (`get_children_by_ids([]), do: []`) emitted nothing on that path; the folded helper wraps
     unconditionally, so an empty-list call now emits a span and issues an empty-array `IN`.
     Restoring the guard is usually the wrong trade — it is dead code at most call sites.
  3. **Previously-untraced hops gain spans.** Folding tends to expose a sibling call that was
     already facade-direct but never instrumented, and leaving one of N identical hops untraced
     is the inconsistency the fold exists to remove. #1269's `fetch_parent/1` is that case.

  Check the boards and triggers before folding an instrumented ACL — #1259 is the precedent,
  where renaming an instrumented module silently moved its span. At the time of writing the
  `live` environment has no `acl.*` columns at all, so nothing queries these attributes yet;
  that is why #1269's renames were safe, and it is not a general licence.
- **A facade read is strongly consistent; a projection is not.** That is sometimes the reason to
  choose it. `provider/assignments.ex:307` reads `ProgramCatalog.get_program_for_provider/2`
  rather than the `provider_programs` projection precisely because an ownership guard cannot
  tolerate projection lag (#1134).
- **Projections remain for hot read paths**, where a per-render facade call would not serve. This
  ADR narrows when an *ACL* is warranted; it does not change CQRS.
- **`boundary-checker` flags the inverse.** It previously reported "a missing ACL where one should
  exist" as a Warning — a false finding against this decision. It now flags an *unnecessary* ACL.
- **`mix lint_acl_boundary` enforces the observability clause** (added for #1274). Review alone did
  not hold it: four of the eight raw-table reads in the tree had drifted untraced, including
  `provider/…/acl/participation_session_stats_acl.ex` — cited by name above as a legitimate ACL —
  and `enrollment.ex`, whose untraced `programs` join hid behind the six `acl_span`s that file
  already carried for its Family hops. That last one is why the lint checks per *function*, not
  per file.

## Precedents in the tree

- `lib/klass_hero/provider/assignments.ex:307` — domain module, facade call inside an `acl_span`
- `lib/klass_hero_web/helpers/provider_display.ex:30` — web helper, bare facade calls (#1195/#1196)
- `lib/klass_hero/messaging/adapters/driven/persistence/queries/conversation_queries.ex:175` —
  query builder calling `ProgramCatalog.list_ended_program_ids/1`

## Supersedes

- ADR 0001's consequence "Cross-context reads go through ACLs/projections" — that clause only. Its
  decision (correlation IDs over foreign keys) and its "never SQL joins across context tables"
  consequence both stand.
