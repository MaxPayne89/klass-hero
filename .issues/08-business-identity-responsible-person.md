# 08 — Business: Identity — responsible person

Type: AFK

## What to build

The business track's B1 step. A business designates a **named responsible person** (owner/director, legally accountable) who completes Stripe Identity verification — reusing the `IdentityVerification` machinery from slice 02, run against the person rather than the business. Capture `responsible_person_name` and role. The checklist labels this "Identity verification — responsible person" to distinguish it from business registration (slice 09).

## Acceptance criteria

- [ ] Business onboarding captures `responsible_person_name` + role on the `ProviderProfile`
- [ ] A Stripe Identity session is created for the responsible person; `IdentityVerification` records the session id
- [ ] `verified` webhook advances B1; `requires_input`/`canceled` fails with retry (reuses slice 02 paths)
- [ ] Step labelled distinctly from business registration in the checklist
- [ ] Only session id + outcome stored; no document images
- [ ] B1 contributes to the business case `:verified`

## Blocked by

- 07 (business entity_type)
- 02 (individual identity — reuses Stripe `IdentityVerification` machinery)

## Supersedes

GitHub #955.
