# Klass Hero is merchant of record, and money moves by separate charges and transfers

The Transaction Ready milestone is the GA blocker: nothing on the platform moves money today. A
booking writes an **Enrollment** with `status: :pending` and zero in every money column, and the
parent either pays the provider in cash or nothing happens at all.

Building the money path forced a decision that is expensive to unwind, because it determines who
is legally selling the service — and therefore what every **Invoice** says. It also sits upstream
of an unanswered VAT question, so it was chosen to keep the charged amount independent of that
answer.

## Decision

- **Klass Hero is merchant of record.** The charge settles on the platform account, so the parent's
  bank statement shows Klass Hero and Klass Hero is the seller of record. The **Rechnung** to the
  parent and the **Gutschrift** to the provider are both Klass Hero documents, which is only
  coherent under this model.

- **Money moves by separate charges and transfers, not destination charges.** Both keep the platform
  as settlement merchant, so both preserve merchant-of-record. The difference is timing: a
  destination charge sets `application_fee_amount` when the PaymentIntent is *created*, whereas the
  real processing fee only exists once the charge has *settled* and appears on the balance
  transaction. Decoupling the transfer is the only way to move an exact remainder.

- **The Processing Fee is the processor's actual cost, passed through at zero margin.** Read from
  the balance transaction, deducted from the **Transfer**. It is a recovered cost, not revenue, and
  it is deliberately **not** the **Success Fee** that ADR-0004 left undesigned. Code, copy and
  invoices must not blur them.

- **Price is gross.** What a provider types is what a parent pays. Net and VAT are derived. This is
  what makes the charged amount invariant to the outstanding VAT question, and it is what German
  consumer price display expects.

- **A new `Billing` bounded context owns the money.** **Payment**, **Transfer**, **Invoice**,
  **Processing Fee** and **Refund** live there. **Enrollment** stays what the glossary says it is —
  a child's commitment to a Program — and **Provider** gains only the connected-account identity.

- **`Invoice` is one immutable entity with three kinds** (`:rechnung`, `:gutschrift`, `:storno`),
  each with its own sequential number series. One concept rather than three because German law
  treats a Gutschrift as an invoice issued by the recipient of the supply (§14 Abs. 2 S. 2 UStG).
  Never edited after issue; a correction is a new Invoice.

- **Stripe webhooks land in a Billing-owned inbox keyed on the Stripe event id**, storing the raw
  payload, acking 200 immediately and processing via Oban. Not the existing `processed_events`
  table, whose `event_id` is an `Ecto.UUID` and which retains no payload to replay or audit.

- **Reconciliation treats Stripe as authoritative but never auto-corrects.** A daily job compares
  our records against Stripe and raises through `error_tracker`; a human decides. Silently
  rewriting financial records would destroy the audit trail the immutable Invoice exists to provide.

## Considered and rejected

- **Direct charges.** The only charge type where the connected account can be made to bear the
  processing fee, which would have solved the fee question outright. Rejected because it makes the
  *provider* the settlement merchant: the provider becomes seller of record, the parent's statement
  shows them, and Klass Hero can no longer issue either document. It trades the whole invoicing
  model for a fee mechanism.

- **Destination charges with an estimated fee.** Simplest to build, and the payout is atomic with
  the charge. Rejected because the estimate is wrong in both directions — a non-EEA card costs
  materially more than an EEA one — and the over-collections are unintended revenue, which drags
  VAT and accounting consequences onto a fee designed to be neutral.

- **Absorbing the processing fee.** Keeps the single-call model and the marketing promise untouched.
  Rejected as a deliberate per-transaction loss that worsens proportionally on cheap bookings.

- **Putting the tax snapshot on `enrollments`.** What the milestone's issues originally specified.
  Rejected because an Enrollment carries mutable lifecycle state, a cancellation would sit next to
  frozen printed figures with only discipline keeping them apart, and a second document for the same
  enrollment (a Storno) has nowhere to live.

## When to revisit

- **When the Success Fee is built.** It is Klass Hero's margin and belongs beside the Processing Fee
  without merging into it. ADR-0004's warning stands: it must not resurrect tier vocabulary.

- **If tax advice treats the Processing Fee as a supply to the provider.** Then it is taxable, Klass
  Hero owes VAT on a fee collected at cost, and zero margin becomes unachievable — at which point
  either the fee stops being a pure pass-through or it is abandoned in favour of absorbing the cost.

- **If the VAT answer makes the platform materially pricier than booking direct.** If provider-level
  exemptions turn out not to travel down the supply chain, merchant-of-record itself becomes the
  thing to reconsider, and this ADR is what would be superseded.
