# Provider Vetting Process

> Canonical specification for provider vetting on Klass Hero. Supersedes the issues in milestone 16
> ("6 Step verification process", individual providers) and milestone 23 ("Business Vetting",
> business-entity providers). **Those issues are now historical intent, not the spec** — they were
> written against a binary, document-only model and will be re-cut against the composable
> `VerificationStep` engine ([ADR-0008](adr/0008-provider-vetting-is-a-composable-step-engine.md)).
> This document is the step catalog; the ADR holds the engine decision.

## Scope and entry point

Vetting gates **the Provider entity**. Per [ADR-0005](adr/0005-staff-and-provider-are-independent-personas.md),
provider-hood is always a deliberate, person-initiated act — never automatic from being hired as
staff. A vetting case therefore attaches to a `ProviderProfile` the moment that profile is created
(self-registration, or a Staff Member explicitly upgrading), and the provider is not approved until
every **required step for their entity type** has passed.

A `ProviderProfile` carries an `entity_type`:

| `entity_type` | Who | Track |
|---|---|---|
| `:individual` | A sole person offering activities (sole trader) | 6-step process (Steps 1–6 below) |
| `:business` | A company, organisation, or registered business | Business track (B1–B5 below) |

`entity_type` is chosen at registration and gates which checklist is shown throughout. It is
**foundational** — it belongs to neither milestone exclusively and should land before either track
is built (see "Open design questions").

---

## Track A — Individual providers (6 steps)

Public-facing framing lives in `KlassHeroWeb.TrustSafetyLive` ("Six checks. No shortcuts.").
A provider is approved only when **all six** steps are approved.

### Step 1 — Identity & Age Verification
- **Goal:** the provider is a real person, ≥ 18, whose identity matches the name on their account.
- **Mechanism:** Stripe Identity. Platform creates a Verification Session
  (`POST /v1/identity/verification_sessions`, configured to require a document so a DOB is returned);
  provider completes the hosted ID scan + liveness selfie.
- **Outcome arrives by webhook, never by the redirect.** The result is asynchronous — the
  `return_url` redirect means "the provider finished the form", not "verified". The session moves
  `processing → verified | requires_input`; only the webhook carries the decision. See ADR-0009.
- **Pass:** `identity.verification_session.verified` webhook, **gated by an 18+ age check** computed
  from `verified_outputs.dob` at webhook-receipt time (`≥ 18` passes). The check is **fail-closed**:
  under 18 fails (`under_18`); missing/unparseable DOB also fails (`age_unverifiable`). Both prompt a
  retry.
- **Fail:** `requires_input` / `canceled` marks the step failed and prompts a retry. `processing`
  events are acknowledged but drive no state change (the step already sits at `:submitted`).
- **Audit:** one `IdentityVerification` row **per session** (retries append, never overwrite) holds
  the Stripe session id (unique), status, pass/fail outcome and failure reason. **No DOB and no
  document images are retained** — the age check keeps only its boolean result. Stripe processes the
  biometric data.
- **Idempotency:** the webhook handler dedups on the session id and is safe under at-least-once /
  out-of-order delivery (approving an already-approved step is a no-op; an unknown session acks 200
  and no-ops).
- **Team involvement:** read-only this slice. A failed/blocked identity step surfaces to Admin with
  its reason; there is **no admin force-approve** for identity (no overriding a biometric outcome).
  An appeal is a provider-initiated retry (new session).
- _Issue #553. Engine + integration shape: ADR-0008 (engine), ADR-0009 (this step)._

### Step 2 — Experience Validation
- **Goal:** at least one year of experience working with children in the provider's area of expertise.
- **Mechanism:** document upload, admin review.
- _Issue #554._

### Step 3 — Extended Background Check
- **Goal:** eligibility to work safely with minors (extended police background check).
- **Mechanism:** document upload, admin review.
- _Issue #555._

### Step 4 — Video Screening
- **Goal:** assess communication skills and alignment with platform values.
- **Mechanism:** video submission + admin review. Public copy on the About and Trust & Safety pages
  describes this step (see #557 for copy alignment).
- _Issues #556 (flow), #557 (copy)._

### Step 5 — Child Safeguarding Certificate
- **Goal:** the provider holds or completes a recognised child-safeguarding course.
- **Mechanism:** certificate upload, with a reference to a free course for providers who need one.
- _Issue #558._

### Step 6 — Community Standards Agreement
- **Goal:** explicit agreement to the Klass Hero Community Guidelines before approval.
- **Mechanism:** scrollable guidelines display + PDF download + checkbox confirmation.
  **Auto-approves on submission** — no admin review.
- **Data:** persist `provider_id`, `agreed_at` (UTC), `guidelines_version` (e.g. `"1.0"`).
  Versioned so material updates require re-agreement.
- _Issue #559. Community Guidelines v1.0 full text: see the PDF attached to #559
  (`Klass_Hero_Community_Standards_Agreement.pdf`) — not reproduced here._

### Onboarding checklist (Track A UI)
A unified dashboard view shows all six steps in order, each with a status
(**Not started / Submitted (pending review) / Approved / Rejected**) and a contextual action button
("Start", "Upload", "Resubmit", "View feedback"). Rejected steps show the admin's reason. Overall
approval status is shown at the top; the profile stays locked until all six are approved.
- _Issue #560._

---

## Track B — Business providers (B1–B5)

A two-track system for business entities. The business designates a **named responsible person**
(owner/director, legally accountable). Verification of the person is tied to the person, not the
entity — **if the responsible person changes, B1 resets, and B4 + B5 reset with it.**

### B1 — Stripe Identity for the named responsible person
- Same Stripe Identity mechanism as Step 1, run against the responsible person.
- Capture `responsible_person_name` and role (e.g. "Jane Smith, Director").
- Checklist label distinguishes this from B2: "Identity verification — responsible person".
- Changing the responsible person resets B1 to "Not started".
- _Issue #955. Also introduces `entity_type` on the profile._

### B2 — Business registration document upload
- Proof the business is a registered entity. Document upload, admin review.
- _Issue #956._

### B3 — Public liability insurance certificate upload
- Document upload, admin review, via a dedicated widget that also captures the policy **expiry date**
  (nullable `expiry_date` on `verification_documents`; required for this type, enforced in the submit
  command, not the shared changeset).
- **Expiry warning (synchronous):** `VerificationDocument.expiry_status/2` classifies the date as
  `:expired | :expiring_soon` (within 30 days) `| :valid`; the provider sees a live warning as they
  pick the date, and admin review shows an expiry badge (AC "policy is current").
- **Deferred:** the *ongoing* obligation — a cert approved today lapsing later — is a separate
  scheduled (Oban) re-flag job with its own delisting-severity decision. Not in this milestone.
- _Issue #957 (synchronous half); expiry re-flag follow-on relates #957 + #558._

### B4 — Community Standards Agreement (business)
- Identical flow to Step 6, signed by the responsible person on behalf of the business.
- **Data:** reuses `community_standards_agreements` with `agreed_by_name` (responsible person) and an
  `entity_type` column so individual vs business agreements are distinguishable in reporting.
- Resets if the responsible person changes.
- _Issue #958._

### B5 — Staff vetting liability attestation
- A legally-grounded **Provider Child Safety Compliance Declaration**, signed by the responsible
  person. Declares that all instructors/staff are background-checked per German law, and commits the
  business to ongoing obligations including indemnifying Klass Hero against staff-related claims.
- **Critical data-minimisation rule:** Klass Hero **never** receives or stores certificate
  contents. The attestation is a contractual declaration only — this keeps the platform outside
  GDPR Article 10 (criminal-record data) scope entirely. The provider inspects certificates itself
  and records only inspection date + pass/fail.
- **Auto-approves** on submission. One-time; re-attestation only when the responsible person changes.
- **Data:** new `staff_liability_attestations` table — `provider_id`, `attested_at` (UTC),
  `attested_by_name`, `attestation_version`.
- **Downstream:** when a business assigns a new instructor, a contextual reminder is shown ("By
  assigning this person as an instructor you confirm they hold a valid erweitertes Führungszeugnis
  and have been vetted per your platform agreement"). Hooks into the instructor role flag (#840).
- _Issue #959._

#### B5 legal basis (must be reviewed by a German-qualified lawyer before shipping)
- **§ 72a SGB VIII** (Bundeskinderschutzgesetz) — exclusion of persons with relevant prior
  convictions from child/youth welfare roles; establishes the *erweitertes Führungszeugnis* as the
  recognised standard of care.
- **§ 30a BZRG** — statutory basis for the erweitertes Führungszeugnis.
- **§ 278 BGB** — provider's near-strict liability to parents for instructor conduct
  (Erfüllungsgehilfen; no exculpation). The attestation allocates this explicitly.
- **§ 823 BGB** — general duty of care; failure to obtain an erweitertes Führungszeugnis for someone
  working alone with children constitutes negligence.
- **GDPR Art. 10 / § 26 BDSG** — criminal-record data minimisation; provider records only inspection
  date + outcome.
- **DSA Art. 28** — proportionate measures for minor safety.
- **Vertragsstrafe** (§ 339 BGB) clause — amount **TBD with legal counsel**; must be proportionate
  (§ 343 BGB, courts can reduce disproportionate penalties).
- **48-hour notification obligation** — provider must notify Klass Hero if any staff member becomes
  subject to a criminal investigation relating to offences against children.

---

## Shared building blocks

Both tracks lean on the same machinery. Today's code does **not** yet model these as first-class
concepts (see "Open design questions"):

| Building block | Track A | Track B | Mechanism |
|---|---|---|---|
| Identity (Stripe) | Step 1 | B1 | Stripe session + webhook outcome (no file) |
| Document + admin review | Steps 2, 3, 5 | B2, B3 | `VerificationDocument` upload → approve/reject |
| Video + admin review | Step 4 | — | submission → approve/reject |
| Community agreement | Step 6 | B4 | consent row, auto-approve (no file) |
| Attestation | — | B5 | signed declaration row, auto-approve (no file) |
| Completion engine | all 6 | all 5 | "all **required** steps approved" → `verified` |

---

## Engine

Both tracks run on one composable, ordered `VerificationStep` engine with hybrid (gated-groups)
ordering, owned by a `VettingCase` aggregate. The design decision, its rationale, and consequences —
the aggregate + lifecycle, the typed evidence split (`VerificationDocument` / `IdentityVerification`
/ `SignedAgreement`), the domain-module track config, reset cascade, and the big-bang migration
behind the unchanged `provider_verified` event contract — are recorded in
[ADR-0008](adr/0008-provider-vetting-is-a-composable-step-engine.md). This document is the step
catalog; the ADR is the decision.

## Status of related artefacts
- **No `provider-verification.allium` spec exists** in the repo or its git history (ADR-0005
  referenced one; it was never committed). Nothing to tend.
- Public copy: `KlassHeroWeb.TrustSafetyLive.verification_steps/0`, About page, For-Providers page.
- Community Guidelines v1.0 full text: PDF on issue #559 (not reproduced here).
