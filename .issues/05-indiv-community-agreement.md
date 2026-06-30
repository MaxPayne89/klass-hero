# 05 — Individual: Community Standards Agreement

Type: AFK

## What to build

The individual track's final step: the provider reads the Klass Hero Community Guidelines (scrollable display + PDF download link) and explicitly agrees via checkbox. On submission a `SignedAgreement{kind: :community_agreement}` record is persisted (`signed_by_name`, `signed_at`, `version`) and the step **auto-approves** — no admin review. Guidelines are versioned so future material updates can require re-agreement.

## Acceptance criteria

- [ ] Community-agreement step definition wired into the individual track (auto-approve, no admin review)
- [ ] Scrollable guidelines + PDF download link + checkbox confirmation UI
- [ ] Submission persists `SignedAgreement{:community_agreement}` with signer, timestamp, version
- [ ] Step auto-approves on submission and contributes to case `:verified`
- [ ] Guidelines version recorded; re-agreement path exists when version changes
- [ ] Community Guidelines v1.0 content sourced from the canonical doc / #559 PDF (not invented)

## Blocked by

- 01 (spine)

## Supersedes

GitHub #559.
