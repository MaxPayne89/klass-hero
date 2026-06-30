# 01 — Vetting engine spine (document steps, inert baseline)

Type: AFK

## What to build

The composable vetting engine from ADR-0006, wired so that **today's behavior is reproduced exactly** — document steps only, emitting the existing integration events. No new step types yet; this is the regression-safe foundation everything else builds on.

End-to-end: a Provider's vetting is a `VettingCase` aggregate owning ordered `VerificationStep` instances, selected by the Provider's `entity_type` from a `Vetting` track domain module. A step is completed by typed evidence; for this slice only the `VerificationDocument` (document) evidence kind is wired. When every required step in the track is `:approved`, the case reaches `:verified` and the existing `VerifyProvider` command fires the unchanged `provider_verified` integration event; a regression of an approved step calls `UnverifyProvider` → `provider_unverified`.

Replaces `CheckProviderVerificationStatus`'s `all_approved?(docs)` derivation. The `IdentityVerification` and `SignedAgreement{kind}` evidence models + `reset_step/2` aggregate method are introduced here as pure domain code (unit-tested in isolation) but not yet triggered by any flow.

## Acceptance criteria

- [ ] `entity_type` (`:individual | :business`, default `:individual`) on `ProviderProfile` (domain + schema + mapper)
- [ ] `Vetting` domain module exposes `track(entity_type) :: [StepDefinition.t()]`; individual track defines the 6 step keys, business track the 5 (B1–B5), each with `completed_via`, `requires`, `admin_review?`
- [ ] `VettingCase` aggregate: owns ordered `VerificationStep` instances, instances frozen from definitions at creation, lifecycle `:not_started → :in_progress → :verified` (reset → `:in_progress`); pure `verified?` and `reset_step/2` (forward reverse-edge cascade) with unit tests
- [ ] `IdentityVerification` and `SignedAgreement{kind}` domain models + persistence introduced (pure + schema), unused by flows yet
- [ ] Step-aware handler replaces `all_approved?`; document-step approval/rejection advances the linked step and recomputes the case
- [ ] `approve/reject_verification_document` commands + admin `verifications_live` rewired to advance a document step (not imply whole-provider verification)
- [ ] **Unchanged contract:** `provider_verified` / `provider_unverified` integration events still emitted by `VerifyProvider`/`UnverifyProvider`; `ProviderProfile.verified` field preserved; Program Catalog + Enrollment untouched
- [ ] Full suite green — existing provider-verification tests pass against the new engine (big-bang, no compat shim)

## Blocked by

None - can start immediately.

## Supersedes

The binary `all_approved?` engine. No single GitHub issue.
