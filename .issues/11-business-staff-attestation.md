# 11 — Business: Staff Vetting Liability Attestation

Type: HITL — the declaration wording MUST be reviewed by a German-qualified lawyer before shipping; the Vertragsstrafe amount is TBD with legal counsel.

## What to build

The business track's B5 step: the named responsible person signs a legally-grounded **Provider Child Safety Compliance Declaration**, persisted as `SignedAgreement{kind: :staff_attestation}` (versioned, `signed_by_name`, `signed_at`). Auto-approves on submission. **Klass Hero never receives or stores certificate contents** — the attestation is a contractual declaration only, keeping the platform outside GDPR Art. 10 scope. Also: when a business assigns a new instructor, show a contextual reminder that the provider confirms a valid erweitertes Führungszeugnis and platform-agreement vetting.

Legal basis (see `docs/6-step-verification-process.md` § B5): § 72a SGB VIII, § 30a BZRG, §§ 278 & 823 BGB, GDPR Art. 10 / § 26 BDSG, DSA Art. 28, plus a Vertragsstrafe (§ 339 BGB, proportionate per § 343) and a 48-hour notification obligation.

## Acceptance criteria

- [ ] B5 step wired into the business track (auto-approve, no admin review)
- [ ] Active informed-acceptance UI (not a small-print checkbox); signatory confirms authority to bind the organisation
- [ ] Persists `SignedAgreement{:staff_attestation}` with version, signer, timestamp; no certificate data stored
- [ ] Declaration text references the required legal framework and includes indemnity, Vertragsstrafe, and 48-hour notification clauses
- [ ] Contextual reminder shown when assigning a new instructor (hooks into instructor role flag, GitHub #840)
- [ ] **Lawyer sign-off on wording + Vertragsstrafe amount recorded before merge**
- [ ] B5 contributes to business case `:verified`

## Blocked by

- 07 (business entity_type)
- 05 (individual community agreement — reuses `SignedAgreement` machinery)

## Supersedes

GitHub #959.
