# A booking authorizes, the provider's acceptance captures, and the program's start releases the money

ADR-0012 settles who sells and how money moves. This one settles *when* — and that turns out to
decide how much machinery the platform needs, because holding money for longer removes whole
categories of failure rather than merely deferring them.

Two facts constrain it. A **Provider** can already accept or decline a pending **Enrollment**
(`Enrollment.confirm/1`, wired from the provider dashboard), so payment success and provider
acceptance both want the same `:pending → :confirmed` transition. And programs can be booked far
ahead — a camp listed in April may not run until August — so the gap between paying and receiving
the service is often months.

## Decision

- **Booking authorizes; it does not charge.** The parent's card is held when they book. No money
  moves yet.

- **Provider acceptance captures, and capture is what confirms the Enrollment.** Neither the parent
  submitting the form nor the provider clicking accept confirms it alone. A decline voids the hold,
  so **no money ever moved and there is nothing to refund** — this is why refund machinery is not
  needed to ship.

- **Silence accepts.** Providers are notified on booking and reminded at days 2 and 5; if they have
  still not acted, the hold is captured on day 6. Card authorizations expire after 7 days for
  online customer-initiated payments, so day 6 is the last safe moment. The parent, who did
  everything right, keeps their place; the provider listed the program publicly with a capacity, and
  capacity and eligibility are already enforced automatically.

- **The Transfer is held until the Program's `start_date`.** Klass Hero holds the money through the
  entire window in which a booking can be cancelled. The provider is paid once delivery begins.

- **`start_date` is required to publish a paid program.** It is currently nullable and, by the
  glossary's own flagged ambiguity, advertised rather than authoritative. Making it required at the
  publish gate stops a Transfer trigger from silently never firing — a money bug that would manifest
  as absence, not error.

- **Cancellation before `start_date` is a full refund**, recorded by a **Storno**. Because Klass Hero
  still holds the funds, the refund is a write against our own balance and is never reclaimed from
  the provider. Cancellation after a program has begun is out of scope and needs a policy.

- **Cash and bank transfer are removed for paid programs.** Free programs (price zero) book with no
  payment at all. This is not merely a second code path: under merchant-of-record, a cash booking
  would create a Klass Hero VAT liability with no Klass Hero cash to pay it from, and the only
  coherent alternative — the provider selling directly — means running two tax models on one
  platform.

- **Payout readiness is a separate publish gate, not a Verification Step.** Publishing requires
  `vetted? AND payout_ready?` as independent predicates. ADR-0008 makes the vetting Track a trust
  engine over three evidence kinds; a connected bank account is commercial readiness, not evidence
  of trust, and would reset and cascade in ways that make no sense for it.

- **Both feature flags are provider-scoped.** `:stripe_payouts` and `:stripe_checkout` — the latter
  on the provider of the program being booked — so a single pilot provider can be switched on end to
  end while every other provider behaves exactly as before. Parents are never subject to a flag.

## Considered and rejected

- **Charge immediately and refund on rejection.** Cleanest UX and providers keep full control.
  Rejected because it makes refunds, reversals and Storno documents GA-blocking, in the one area
  with no existing code at all.

- **Removing the provider's veto.** Capacity and eligibility are already automatic, so the manual
  accept is arguably redundant, and dropping it would remove the expiry problem entirely. Rejected
  because declining a specific child — on age suitability or support needs — is a control worth
  keeping for children's activities.

- **Approve first, then ask the parent to pay.** No holds, no refunds, nobody over-committed.
  Rejected as a materially different product: "book" becomes "request", the parent must return in a
  second session, and drop-off is real.

- **Transferring as soon as the payment settles.** Best provider cash flow and the simplest state
  machine. Rejected because Klass Hero would hold nothing against a cancellation, and every refund
  becomes a clawback against a provider who may already have been paid out to their bank — the loss
  Stripe explicitly holds platforms responsible for.

- **Tiered or provider-set refund policies.** More market-realistic and fairer to providers on late
  cancellations. Rejected for GA because partial refunds require partial Storno documents and a
  provider share on cancelled bookings, which means transfers must fire for cancellations too.

## When to revisit

- **Cancellation after a program has begun**, which this ADR leaves unspecified and which real usage
  will force.
- **Refund policy generally**, once providers start losing income to late cancellations that a full
  refund makes entirely their problem.
- **Auto-capture on silence**, if providers turn out to resent enrollments they never reviewed, or
  if card network authorization windows change.
- **The transfer trigger**, if Sessions ever become generated from the Program schedule rather than
  hand-created — the glossary flags that as a known gap, and the real start of delivery is the first
  Session, not an advertised date.
