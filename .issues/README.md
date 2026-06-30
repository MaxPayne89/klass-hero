# Provider Vetting — scratch issue breakdown

Local planning artifacts (gitignored). Source of truth:
- **ADR-0006** `docs/adr/0006-provider-vetting-is-a-composable-step-engine.md` — the engine decision
- **Catalog** `docs/6-step-verification-process.md` — the step definitions
- **Glossary** `CONTEXT.md` — Vetting, Vetting Case, Verification Step, Track, Identity Verification, Signed Agreement

Tracer-bullet vertical slices, dependency order. `01` is the spine; everything depends on it.

| # | Slice | Type | Blocked by | Supersedes (GitHub) |
|---|---|---|---|---|
| 01 | Spine — engine + document steps, inert baseline | AFK | — | binary engine |
| 02 | Indiv: Identity & Age (Stripe) | HITL | 01 | #553 |
| 03 | Indiv: document steps (experience, background, safeguarding) | AFK | 01 | #554, #555, #558 |
| 04 | Indiv: Video Screening | AFK | 01 | #556, #557 |
| 05 | Indiv: Community Standards Agreement | AFK | 01 | #559 |
| 06 | Indiv: onboarding checklist UI | AFK | 01 | #560 |
| 07 | Business: entity_type selection at registration | AFK | 01 | part of #955 |
| 08 | Business: Identity — responsible person | AFK | 07, 02 | #955 |
| 09 | Business: document steps (registration, insurance) | AFK | 07 | #956, #957 |
| 10 | Business: Community Standards Agreement | AFK | 07, 05 | #958 |
| 11 | Business: Staff Vetting Liability Attestation | HITL | 07, 05 | #959 |
| 12 | Business: responsible-person change → reset + cascade | AFK | 08, 10, 11 | — |
| 13 | Business: onboarding checklist UI | AFK | 07 | — (new) |

**Moot GitHub milestones:** 16 ("6 Step verification process") and 23 ("Business Vetting") — superseded as mapped above. Close/relabel when these land.
