# 13 — Business: onboarding checklist UI

Type: AFK

## What to build

The business-track equivalent of the individual checklist (slice 06): a unified dashboard view showing the B1–B5 steps in order, each with status and a contextual action button, rejected steps showing the admin reason, overall `VettingCase` status at top, profile locked until `:verified`. Renders whatever the business track defines, so it stays correct as B-steps land.

## Acceptance criteria

- [ ] Checklist renders the business track (B1–B5) in order with per-step status from the `VettingCase`
- [ ] Distinct labels (e.g. "Identity verification — responsible person" vs "Business registration")
- [ ] Contextual action per step; rejected steps show the admin reason
- [ ] Overall case status at top; locked until `:verified`
- [ ] Mobile-first; degrades gracefully with a partial track

## Blocked by

- 07 (business entity_type)

## Supersedes

None — no direct GitHub issue (business analogue of #560).
