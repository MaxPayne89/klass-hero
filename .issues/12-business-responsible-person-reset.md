# 12 — Business: responsible-person change → reset + cascade

Type: AFK

## What to build

When a business changes its named responsible person, the identity step (B1) resets to `:not_started`, and the `requires` cascade resets every dependent step — the Community Standards Agreement (B4) and the Staff Vetting Liability Attestation (B5) must be re-completed by the new responsible person. This wires the trigger to the pure `VettingCase.reset_step/2` aggregate method (built in the spine). Because it is a same-context, same-DB change, the reset happens in the responsible-person-change command's transaction — not via an integration event. Stale evidence (old `IdentityVerification`, old `SignedAgreement`s) is kept for audit; re-submission creates fresh evidence. If the case was `:verified`, it drops to `:in_progress` and `provider_unverified` fires.

## Acceptance criteria

- [ ] Changing `responsible_person_name` triggers `VettingCase.reset_step(:identity_responsible_person)` in the same transaction
- [ ] Cascade resets B4 + B5 (transitive dependents of B1) to `:not_started`
- [ ] A previously `:verified` business drops to `:in_progress` and emits `provider_unverified`
- [ ] Stale evidence retained for audit; new attempts create new evidence records
- [ ] Tests cover: reset cascade set, verified→in_progress transition, event emission, audit retention

## Blocked by

- 08 (B1 responsible-person identity)
- 10 (B4 community agreement)
- 11 (B5 attestation)

## Supersedes

None — new behavior from ADR-0006's reset semantics.
