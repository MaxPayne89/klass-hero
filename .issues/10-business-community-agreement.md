# 10 — Business: Community Standards Agreement

Type: AFK

## What to build

The business track's B4 step: identical flow to the individual Community Standards Agreement (slice 05), signed by the named responsible person on behalf of the business. Reuses `SignedAgreement` — adds `signed_by_name` (the responsible person from B1) and an `entity_type` distinction so individual vs business agreements are separable in reporting. Auto-approves on submission.

## Acceptance criteria

- [ ] B4 step wired into the business track (auto-approve, no admin review)
- [ ] Reuses slice 05 agreement UI; records `SignedAgreement{:community_agreement}` with `signed_by_name` = responsible person and entity_type = `:business`
- [ ] Individual vs business agreements distinguishable in reporting
- [ ] B4 contributes to business case `:verified`
- [ ] (Reset wiring — re-agree on responsible-person change — handled in slice 12)

## Blocked by

- 07 (business entity_type)
- 05 (individual community agreement — reuses `SignedAgreement` machinery)

## Supersedes

GitHub #958.
