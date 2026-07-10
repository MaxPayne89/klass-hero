# Stripe Identity step: the webhook is the source of truth, and the age gate is fail-closed

The individual track's first step (ADR-0008) is completed by Stripe Identity. Stripe Identity
decides asynchronously: a provider finishes the hosted ID scan, gets redirected to our `return_url`,
but the verification result usually is not ready yet — the session sits at `processing` and later
flips to `verified` or `requires_input`, delivered only by webhook. This shapes several decisions a
future reader would otherwise question.

## Decision

- **The webhook is the only source of truth; the redirect is not.** Reaching `return_url` means "the
  provider finished the form", never "verified". The step transitions to `:approved` / failed solely
  on the `identity.verification_session.verified` / `requires_input` / `canceled` webhook events. A
  `processing` event is acked (200) but drives no state change. Anyone tempted to read the result
  synchronously off the redirect is reading a value that does not exist yet.

- **The age gate is fail-closed.** The 18+ check is computed from `verified_outputs.dob` at
  webhook-receipt time, `≥ 18` passes. Under 18 fails (`under_18`); a **missing or unparseable DOB
  also fails** (`age_unverifiable`), never auto-passes. Fail-open is unacceptable on a child-safety
  platform — an un-aged person must not slip through because Stripe returned no DOB. The session is
  configured to require a document so a DOB is attempted. Both failure modes prompt a provider retry.

- **Identity feeds the `VettingCase` by the same path as a document step.** The flow is
  webhook → `StripeWebhookController` (driving adapter; signature-verify + parse only) →
  `RecordIdentityVerificationOutcome` command (idempotent persist + **age gate here** + emit a
  `:identity_verification_passed | :identity_verification_failed` domain event) →
  `AdvanceVettingStepOnIdentityOutcome` handler (approve or reset the `:identity` step, recompute the
  case, call the unchanged `VerifyProvider` / `UnverifyProvider`). The age/Stripe decision is baked
  into *which* event fires, so the handler stays symmetric with the document handler — by the time
  the aggregate is touched, identity and document evidence are indistinguishable. All in-context,
  same-DB → a plain domain event, not an Oban integration event. The only integration event remains
  the unchanged `provider_verified`.

- **Evidence is one `IdentityVerification` row per session, append-only.** A retry creates a new
  Stripe session and a new row; the step's `evidence_ref` points at the current one. The unique
  session id is the idempotency key (at-least-once, out-of-order safe: re-approving is a no-op; an
  unknown session acks 200 and no-ops). Only session id + status + outcome + failure reason persist —
  no DOB, no images.

- **No admin force-approve for identity this slice.** A failed/blocked identity step surfaces to
  Admin read-only (status + reason); Admin cannot override a biometric outcome. An "appeal" is a
  provider-initiated retry. Adding a manual override later is possible but deliberately excluded now.

- **Test doubles maximise local↔CI parity by swapping the transport, not the code.** One real
  `StripeIdentityAdapter` runs everywhere; CI/test inject a `Req.Test` plug via `:stripe_req_options`
  (the established `ResendEmailContentAdapter` pattern), so request-building and response-parsing are
  exercised identically — only the HTTP transport differs. There is **no hand-rolled stub adapter**
  for session creation (it would drift from the real code path). The `ForVerifyingIdentity` port is
  retained as the boundary so the command/handler can be tested with no Stripe at all. On the inbound
  side, parity rests on three rules: (1) one fixtures source — real recorded Stripe session + event
  JSON, captured once from the sandbox, feeds both the outbound `Req.Test` stubs and the inbound
  webhook replays; (2) signature verification is unit-tested with a computed Stripe-scheme HMAC, not
  merely disabled, even though flow tests flip `verify_webhook_signature: false`; (3) fixtures are
  real recorded payloads, never invented, so they match Stripe's actual envelope. The only
  local-vs-CI differences are `:stripe_req_options` (real vs `Req.Test`) and the
  `verify_webhook_signature` flag — both pre-existing knobs.

- **Secrets are runtime config, read lazily.** `STRIPE_SECRET_KEY` → `config :klass_hero, :stripe`
  (consumed by the adapter) and `STRIPE_WEBHOOK_SECRET` → `config :klass_hero, :stripe_webhook_secret`
  (consumed by the signature plug) are read in `runtime.exs`, mirroring `RESEND_API_KEY` /
  `RESEND_WEBHOOK_SECRET`. Unlike `RESEND_API_KEY`, a missing key does **not** raise at boot —
  identity is an unlaunched feature, so the adapter returns `{:error, :stripe_not_configured}` at call
  time and the app boots without it. The two secrets have distinct consumers and are never crossed.

## Considered and rejected

- **Read the result from the `return_url` redirect.** Impossible — the result is asynchronous and
  often not ready at redirect time; the redirect is also user-controlled (they can abandon).
- **Fail-open / route missing-DOB to manual review.** Rejected: weakens the safety guarantee and
  adds an admin workflow the catalog explicitly keeps minimal.
- **Fold record + advance into one command (skip the domain event).** Rejected: breaks the
  "same path as a document step" symmetry and couples the aggregate advancement to Stripe specifics.
- **A separate `:under_review` step status for Stripe `processing`.** Rejected: reuse `:submitted` —
  no new state-machine status, no migration churn; admin sees it as pending.
- **A hand-rolled `StubIdentityAdapter` for session creation.** Rejected for parity: a second adapter
  drifts from the real one and CI would never exercise the real request/response code. `Req.Test`
  transport injection on the one real adapter keeps the code path identical.

## When to revisit

- If a track ever needs an admin to override a Stripe outcome out-of-band, add an explicit
  force-approve command + audit — do not quietly relax the fail-closed gate.
- If Stripe adds a delivery guarantee or a synchronous result API that removes the async gap,
  the "webhook is the only truth" stance can be re-examined.

Reference: step catalog `docs/6-step-verification-process.md` (Step 1); engine ADR-0008; glossary
`CONTEXT.md` (Identity Verification, Verification Step, Vetting Case).
