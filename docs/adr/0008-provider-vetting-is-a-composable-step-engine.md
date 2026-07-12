# Provider vetting is a composable, ordered step engine

Provider vetting must serve two tracks — individual providers (milestone 16, six steps) and business
providers (milestone 23, B1–B5) — that share most machinery: a Stripe identity step, document-and-
admin-review steps, a community agreement, and a single "approved when complete" gate. The existing
foundation cannot express this. `CheckProviderVerificationStatus` verifies a provider when
`Enum.all?(docs, &(&1.status == :approved))` — binary, document-only, with no notion of a required
step-set, step identity, per-step status, entity-type-dependent requirements, or non-document steps
(Stripe / agreement / attestation carry no `file_url` and do not fit `VerificationDocument`).

Building either track on that engine would bolt per-step booleans onto the profile or abuse
`VerificationDocument` for non-documents — the coupling we are trying to avoid.

## Decision

- **Vetting is an ordered, composable list of `VerificationStep`s.** The engine knows how to run a
  list of steps; it never hardcodes *which* steps. Membership and order are **data**, so a sequence
  can be reordered or a step added/removed without touching the engine.
- **A track is a configured sequence selected by `entity_type`** (`:individual | :business`, a field
  on `ProviderProfile`). `entity_type` lands as a standalone foundation change before either track,
  because the step model reads it and both tracks gate on it.
  - `:individual` → `[identity, experience, background, video, safeguarding, community_agreement]`
  - `:business`   → `[responsible_person_identity, business_registration, insurance, community_agreement, staff_attestation]`
- **A step definition** declares its `key`, how it completes (`completed_via` ∈ {document approval,
  Stripe webhook, agreement, attestation}, whether admin review is needed), and an optional
  `requires: [step_key]` prerequisite list. **A step instance** (per provider) carries `status`
  (`:not_started | :submitted | :approved | :rejected`) plus audit fields, and copies its
  definition's structural fields (`key`, `completed_via`, `requires`, `admin_review?`) **at case
  creation** — frozen, so reordering a track later never mutates an in-flight case.
- **The aggregate is an explicit `VettingCase` domain struct**, not an implicit recompute. One per
  Provider, it owns the ordered step instances and moves through a lifecycle
  `:not_started → :in_progress → :verified` (reset → `:in_progress`). The case is self-contained: it
  computes its own `verified?` and cascade from its frozen step instances, never consulting the track
  module after creation. Granular `:submitted` / `:rejected` live on the steps, not the case.
- **Track config lives in a pure domain module** (`Provider.Domain.Services.Vetting`,
  `track(entity_type) :: [StepDefinition.t()]`), not `config.exs` (reserved for DI wiring) and not
  the DB. Track composition is domain policy — version-controlled, unit-tested, reordered via PR.
- **Step evidence is typed and decoupled.** A step holds only a thin `evidence_ref`; the evidence
  lives in dedicated records that drive step status: `VerificationDocument` (the 6 document steps,
  reused as-is), `IdentityVerification` (Stripe session id + outcome), and `SignedAgreement{kind}`
  (one model for both `:community_agreement` and `:staff_attestation` — same shape, different legal
  text).
- **Reset is a pure aggregate method** — `VettingCase.reset_step(case, key)` sets the step plus all
  transitive dependents (reverse-edge traversal of `requires`) to `:not_started` and recomputes the
  lifecycle. Triggered in-transaction by the responsible-person-change command (same DB → not an
  integration event); stale evidence is kept for audit, re-submission creates fresh evidence.
- **Ordering is hybrid (gated groups), not a strict chain.** Most steps have no prerequisite and run
  in parallel; a few declare a real dependency. A step is startable only when all its `requires`
  steps are `:approved`. This models the business reset cascade directly: `community_agreement` and
  `staff_attestation` both `require` `responsible_person_identity`, so a responsible-person change
  that resets identity cascades to reset them too. The prerequisite graph must be acyclic.
- **Verified = every step in the provider's track is `:approved`.** Documents become *one way a step
  passes*, not the unit of verification. The `provider.verified` fact other contexts already consume
  is preserved as the engine's output contract — same boundary truth, new internals.

## Consequences

- The binary `all_approved?` engine and `VerificationDocument`-as-unit-of-verification are
  **superseded**. Existing vetting artifacts (the binary engine, the milestone 16/23 issues written
  against it) are historical intent, re-cut against this model. `VerificationDocument` is retained
  only as the *document-shaped* evidence, losing its role as the verification unit; step identity
  moves out of `valid_document_types` into step definitions.
- **The cross-context contract is the immovable boundary.** The `integration:provider:provider_verified`
  / `provider_unverified` events (consumed by Program Catalog's `program_listings` + `verified_providers`
  projections and Enrollment's `create_enrollment`) and the `ProviderProfile.verified` field do **not**
  change. `VerifyProvider` / `UnverifyProvider` keep emitting them; the new handler calls those same
  commands when a `VettingCase` crosses `:verified`. Every cross-context consumer stays untouched.
- **Migration is big-bang, not strangler** — there is no live vetting data to preserve, so one PR
  replaces the internal derivation outright (no parallel-run, no compat shim). "Big-bang" is scoped to
  the *provider-internal* machinery; it does not touch the integration-event contract above.
  `CheckProviderVerificationStatus`'s `all_approved?` is replaced by the step-aware handler; the
  `approve/reject_verification_document` commands and admin `verifications_live` are rewired to advance
  the linked document step rather than imply whole-provider verification.
- The catalog of steps and tracks lives in `docs/6-step-verification-process.md` (reference); this
  ADR holds the decision; `CONTEXT.md` holds the glossary (Vetting, Vetting Case, Verification Step,
  Track, Identity Verification, Signed Agreement).

## When to revisit

- If a third track appears (e.g. real per-staff vetting, today only proxied by the business B5
  attestation), confirm the `entity_type`-keyed selection still fits or generalise to a named-track
  registry.
- If order needs to be editable by admins at runtime (not just in code), promote the track config
  from a domain module to DB-backed data.
