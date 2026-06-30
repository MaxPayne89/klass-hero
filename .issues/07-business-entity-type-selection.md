# 07 — Business: entity_type selection at registration

Type: AFK

## What to build

Provider registration asks whether the applicant is an individual or a business entity, setting `entity_type` on the `ProviderProfile`. This selection gates which track (and therefore which checklist and steps) the provider's `VettingCase` runs throughout. Business providers additionally capture the basics needed to start the business track.

The `entity_type` field itself lands in the spine (01); this slice delivers the **selection UX** and the branch that routes a business registrant onto the business track.

## Acceptance criteria

- [ ] Registration presents an individual-vs-business choice, persisting `entity_type`
- [ ] A `:business` profile's `VettingCase` is created from the business track (B1–B5); `:individual` from the 6-step track
- [ ] Choice is reflected in the dashboard (which checklist the provider sees)
- [ ] Tests cover both branches selecting the correct track

## Blocked by

- 01 (spine)

## Supersedes

Part of GitHub #955 (the entity_type gate).
