# 02 — Individual: Identity & Age Verification (Stripe)

Type: HITL — first Stripe Identity integration. Human-only parts are **go-live only** (Stripe sandbox
secret key, webhook signing secret, one manual `stripe listen` end-to-end pass); the whole slice
builds and tests AFK behind `Req.Test`. Decisions locked + documented in **ADR-0007** and
**`docs/6-step-verification-process.md` Step 1**.

## What to build

The individual track's Identity step, completed via Stripe Identity, feeding the `VettingCase` by the
**same path as a document step** (ADR-0006). The platform creates a Verification Session; the provider
completes the hosted ID scan + liveness selfie; the outcome arrives **by webhook, never by the
redirect** (the result is asynchronous — `processing → verified | requires_input`).

End-to-end flow:

- A `:identity` step is added to the individual track as step 1 (`completed_via: {:stripe_identity}`,
  `admin_review?: false`, no `requires` edges this slice — independent of the document steps).
- `CreateIdentityVerificationSession` calls Stripe via a `ForVerifyingIdentity` port (one real
  `StripeIdentityAdapter`, raw `Req`, **no hand-rolled stub** — `Req.Test` transport injection mirrors
  `ResendEmailContentAdapter`), persists an `IdentityVerification` row with the session id, and submits
  the step (`:submitted`).
- `StripeWebhookController` (driving adapter; signature-verify + parse only) →
  `RecordIdentityVerificationOutcome` command (idempotent persist; **age gate runs here**, fail-closed;
  emits `:identity_verification_passed | :identity_verification_failed` domain event) →
  `AdvanceVettingStepOnIdentityOutcome` handler (passed → `approve_step(:identity)` → if `verified?`,
  `VerifyProvider`; failed → `reset_step(:identity)`). Handler is symmetric with the document handler.
- The onboarding return page lands on the checklist, renders the current step state, and
  **live-updates via PubSub** ("verification in progress" → approved ✓ / failed + Retry). Retry =
  a new session (new row). Reaching `return_url` is never treated as success.

Evidence is one `IdentityVerification` row **per session** (retries append, never overwrite): session
id (unique), status (`:processing | :verified | :requires_input | :canceled`), outcome
(`:pass | :fail | nil`), failure reason. **No DOB and no document images persisted** — the age check
keeps only its boolean result.

## Acceptance criteria

- [ ] `:identity` step added to the individual track (step 1, `{:stripe_identity}`, auto-approve, no
      `requires`); `StepDefinition.completed_via` type extended to admit it
- [ ] `IdentityVerification` model + persistence (append-only, one row per session): session id
      (unique), status, outcome, failure reason — no DOB, no images
- [ ] `ForVerifyingIdentity` port + `StripeIdentityAdapter` (raw `Req`, reads `:stripe_req_options`);
      `CreateIdentityVerificationSession` records the session id and submits the step
- [ ] `identity.verification_session.verified` webhook → step `:approved`, **gated by a fail-closed
      18+ check** from `verified_outputs.dob` (`≥18` passes; `under_18` and `age_unverifiable` both
      fail with a retry prompt); session configured to require a document so a DOB is attempted
- [ ] `requires_input` / `canceled` → step failed + retry prompt; `processing` acked (200) with no
      state change
- [ ] Webhook is idempotent (dedup on session id; re-approve is a no-op; unknown session acks 200 and
      no-ops; out-of-order safe — act only on terminal events)
- [ ] Step approval feeds the `VettingCase` the same way as a document step → contributes to
      `:verified` via the unchanged `VerifyProvider` / `provider_verified`
- [ ] Webhook endpoint secured: Stripe-scheme signature verification (its own plug — not the Svix
      one), unit-tested with a computed HMAC; failed/blocked identity step surfaces **read-only** to
      Admin (no force-approve)
- [ ] Return page live-updates via PubSub (in-progress → approved/retry); redirect never treated as
      success
- [ ] Secrets in `runtime.exs`: `STRIPE_SECRET_KEY` → `:stripe`, `STRIPE_WEBHOOK_SECRET` →
      `:stripe_webhook_secret`, read lazily (no boot raise; adapter returns `{:error,
      :stripe_not_configured}` when absent)
- [ ] Local↔CI parity: one real adapter + `Req.Test` injection; `verify_webhook_signature` flag off in
      test/CI; **real recorded** Stripe session + event fixtures (one source) drive both outbound stubs
      and inbound webhook replays
- [ ] Full suite green; no new dependency added

## Decisions & docs

- ADR-0007 — webhook-is-truth, fail-closed age gate, record→event→advance mirroring, no force-approve,
  `Req.Test` parity, lazy secrets.
- ADR-0006 — the composable step engine (`VettingCase`, typed evidence, track policy).
- `docs/6-step-verification-process.md` Step 1 — the step catalog.

## Blocked by

- 01 (spine) — done (commit 145ed07f).

## Supersedes

GitHub #553.
