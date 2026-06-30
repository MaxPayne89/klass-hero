# 09 — Business: document steps (Registration, Insurance)

Type: AFK

## What to build

Two business-track steps on the existing `VerificationDocument` upload + admin-review machinery:

- **B2 Business registration** — proof the business is a registered entity.
- **B3 Public liability insurance** — insurance certificate.

Each: provider uploads → admin approves/rejects → step advances → business `VettingCase` recomputes. Rejected steps show the admin reason.

## Acceptance criteria

- [ ] B2 + B3 step definitions wired into the business track with distinct document types
- [ ] Upload → admin approve/reject advances the linked step (reuses document flow)
- [ ] Rejection reason shown per step
- [ ] Each approved step contributes to business case `:verified`; tests cover approve + reject

## Blocked by

- 07 (business entity_type)

## Supersedes

GitHub #956, #957.
