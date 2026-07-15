# The Responsible Person is a Provider value, and changing it is the business track's sole vetting reset

A `:business` **Provider** designates a **Responsible Person** — the owner/director legally
accountable for the business on Klass Hero. The business vetting track (ADR-0008) ties three steps
to *that person* rather than the business entity: the Stripe **Identity Verification** (B1) runs
against them, and the business **Community Agreement** (B4) and **Staff Attestation** (B5) are signed
on their authority. The spec's rule — *"if the responsible person changes, B1 resets, and B4 + B5
reset with it"* — forces a decision about what a "change" *is* and how it propagates. ADR-0008
already decided the reset is an in-transaction cascade over the `requires` graph; this ADR decides
how the person is modelled and what triggers that cascade. A future reader looking at the code will
otherwise wonder why editing a name field can unverify an approved business, and why there is only
one command touching the responsible person.

## Decision

- **The Responsible Person is a value on the Provider, not a first-class entity.** Two fields —
  `responsible_person_name` and `responsible_person_role` — on the `providers` table. There is no
  `responsible_people` table and no history of past holders. The one fact that must be snapshotted
  when it matters — *who signed* B4/B5 — is already captured on each append-only `SignedAgreement`
  (`signed_by_name`), so the person needs no independent lifecycle of its own.

- **A single idempotent command is the only mutator, and the only reset trigger.**
  `set_responsible_person(provider_id, name, role)` compares the submitted `(name, role)` against
  the stored values by **exact match** and returns a typed outcome:
  - equal → `:unchanged`, a no-op (this is the deliberate typo-guard: correcting "Jane Smtih" to
    "Jane Smith" is *not* a change and must not nuke a passed identity check);
  - first set → `:set`, persist only;
  - genuine change → `:changed`, persist, `reset_step(:responsible_person_identity)` (which cascades
    to B4 + B5 via the `requires` graph), and unverify the provider if it was `:verified`.

  No general profile-edit path may write these fields. Modelling "the responsible person changed" as
  an explicit command — not a diff detected by a generic form handler — keeps *data change* and
  *domain event* from collapsing into one another. The reset fires on intent, in one transaction,
  same-DB, never as an event (ADR-0008).

- **The change flow works in any lifecycle state, including `:verified`.** A director leaving after
  approval is expected, not an edge case: the command unverifies the business (reusing
  `VettingVerificationSync.maybe_unverify/2`, system-driven, `reviewer_id: nil`) and the new person
  must pass B1 and re-sign B4/B5 before the business is listed again. B2 (business registration) and
  B3 (insurance) do **not** reset — they are facts about the business entity, independent of who is
  accountable, and carry no `requires` edge to identity.

- **There is one UI surface, not two.** The B1 step renders the name/role inputs (pre-filled if set)
  plus a start button; editing the name and resubmitting *is* the change flow. A single facade
  command, `start_responsible_person_verification/4`, wraps set-then-start in one transaction
  boundary so the LiveView never holds the torn intermediate state where the person is saved but no
  identity session is in flight.

## Considered and rejected

- **A `ResponsiblePerson` entity with its own table and history.** Rejected as overkill: nothing in
  the milestone needs an audit trail of past responsible persons, and the consent history that *does*
  matter is already append-only on `SignedAgreement`.

- **Two commands (`set` for first capture, `change` for replacement).** Rejected because it pushes
  set-vs-change state-awareness into the LiveView, the orchestration we keep out of the web layer.
  One idempotent command owning the change-detection is both simpler and the project's idempotency-first
  default.

- **Detecting a change by diffing the name on a general profile-edit form.** Rejected: it conflates a
  typo correction with a deliberate change of the accountable person, and would tempt a future reset
  from an incidental edit handler — the exact coupling this ADR exists to prevent.

## Consequences

- Because `entity_type` cannot switch after profile completion, and a business's registration
  identity lives on the immutable `providers` row, the only thing that legitimately changes the
  vetting picture post-approval is the responsible person — so this command is the single
  post-verification un-listing path for a business, and must be exercised as such in tests.
- The `:unchanged | :set | :changed` return is load-bearing for UI messaging ("Identity reset —
  please re-verify" appears only on `:changed`); callers must not discard it.
