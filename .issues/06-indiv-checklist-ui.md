# 06 — Individual: onboarding checklist UI

Type: AFK

## What to build

A unified checklist view in the provider dashboard showing all individual-track steps in order, each with a status (**Not started / Submitted (pending review) / Approved / Rejected**) and a contextual action button ("Start", "Upload", "Resubmit", "View feedback"). Rejected steps show the admin's reason. Overall vetting status (the `VettingCase` lifecycle) is shown at the top; the profile stays locked until the case reaches `:verified`. The checklist renders whatever the track defines, so it stays correct as steps are added.

## Acceptance criteria

- [ ] Checklist renders the individual track's steps in order with per-step status from the `VettingCase`
- [ ] Contextual action per step; rejected steps show the admin reason
- [ ] Overall case status shown at top; locked until `:verified`
- [ ] Mobile-first; renders correctly with a partial track (steps not yet implemented degrade gracefully)

## Blocked by

- 01 (spine)

## Supersedes

GitHub #560.
