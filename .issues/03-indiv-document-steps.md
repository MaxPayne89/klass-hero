# 03 — Individual: document steps (Experience, Background, Safeguarding)

Type: AFK

## What to build

Three individual-track steps that share the existing `VerificationDocument` upload + admin-review machinery, differing only by document type and copy:

- **Experience Validation** — proof of ≥ 1 year working with children in the provider's area.
- **Extended Background Check** — extended police background check.
- **Child Safeguarding Certificate** — recognised safeguarding course certificate, with a reference to a free course for providers who need one.

Each is a document-evidence step: provider uploads → admin approves/rejects → step status advances → `VettingCase` recomputes. Rejected steps show the admin's reason for resubmission.

## Acceptance criteria

- [ ] Three step definitions wired into the individual track with distinct document types
- [ ] Upload → pending → admin approve/reject advances the linked step (reuses existing `VerificationDocument` flow from spine)
- [ ] Safeguarding step surfaces the free-course reference
- [ ] Rejection reason shown to the provider per step
- [ ] Each approved step contributes to case `:verified`; tests cover approve + reject paths

## Blocked by

- 01 (spine)

## Supersedes

GitHub #554, #555, #558.
