# 22. Notification emails dispatch from the outbox, gated in Accounts

Date: 2026-08-26

## Status

Accepted

## Context

#1071 added the first email the platform sends *because of a preference* rather
than because of a transaction. Three more are queued behind it — #829
(enrollment confirmation), #798 (incident-report parent notification), #742
(incident_reported owner + admin escalation) — and #742 asks the question
outright: "New driving event handler in some context (Provider?
Notifications?)".

Before #1071 there were three email notifier modules, in three contexts
(`Accounts.UserNotifier`, `Enrollment…InviteEmailNotifier`,
`Provider.IncidentReportedEmailNotifier`). None consulted any preference. Two
shared only `Shared.EmailHtml`. Whatever #1071 did was going to be copied three
times, so the shape mattered more than the feature.

Two questions had to be answered together: **where does the dispatch live**, and
**where does the gate live**.

## Decision

### 1. A notification email is dispatched by an event consumer in the context that owns the event

Not by a call inside the producing use case.

`domain-architecture.md` says a same-context reaction is an ordinary function
call made inside the producer's transaction, "so the write and its consequence
commit together". Read literally, Messaging consuming its own `message_sent`
violates that. It does not, because the rule's justification is about
**database** writes.

An email cannot be rolled back. If it is sent inside the producing transaction
and that transaction then fails, the mail is already gone. So it must happen
*after* commit, at-least-once, with retry — which is precisely the transactional
outbox from ADR-0014. Two further consequences of sending inline decided it:

- A user-facing write would carry a participants query, an Accounts query, and
  up to N job inserts. A program broadcast is one message to every enrolled
  family, so N is routinely in the hundreds.
- A person's message would fail to send because Resend was briefly unavailable.

It must be a **handler**, not a projection. `Shared.Projection.project/1`
discards its callback's return value and always answers `:ok`, so a projection
would swallow every dispatch failure — no retry, no compensation, no
dead-letter. A `ForHandlingEvents` consumer propagates `{:error, reason}` back
to `EventDeliveryWorker`.

### 2. The user-preference gate is one contract, owned by Accounts

`users.disabled_email_notifications` is a `{:array, Ecto.Enum}` of the kinds a
user has switched **off**. Absence means enabled, which is what gives every
existing row — and every kind added later — a default of ON with no backfill and
no three-way nil/false/missing ambiguity.

Producing contexts never touch the column. They ask:

- `Accounts.email_notification_enabled?(user_or_id, kind)` — one recipient;
- `Accounts.notifiable_recipients(user_ids, kind)` — bulk, shaped like the
  existing `Accounts.get_display_names/1`.

Adding a user-togglable notification is one atom in the field's `values:` and
one checkbox in the settings card.

### 3. A gate that is not a user preference stays in its own context

This is the half that keeps the contract honest. Of the three queued issues,
**none** is gated by a user preference:

- #798's gate is a per-report toggle the provider sets at submission time.
- #742's gate is the report's severity.
- #829 is transactional confirmation of an action the user just took.

So they must **not** route through `Accounts.notifiable_recipients/2`. Doing it
"for consistency" would let a parent's *message* preference silently veto an
*incident* email — the wrong axis entirely.

### 4. No shared dispatcher

Three designs were generated for #1071, including a full registry (config map +
behaviour + generic dispatcher + generic worker). It was rejected: it builds a
second dispatch system beside `ForHandlingEvents` before a second notification
exists in code, and it carries two vocabularies nothing keeps in sync.

What is genuinely shared is already shared: `Shared.RateLimitedEmailWorker`,
`Shared.EmailHtml`, `KlassHero.Mailer`, and now the Accounts gate. Each feature
writes its own consumer, worker and notifier — roughly 25–40 lines of
recognisable scaffolding.

Per `workflow.md`'s "Second Occurrence Escalates", revisit when either: a second
genuine **user-level** preference is requested, or a **fourth** bespoke email
notifier is about to be written.

## Consequences

- Adding a notification means: a consumer in the owning context, a worker, a
  notifier, one registry line in `:event_consumers`, and — only if it is
  user-togglable — one atom and one checkbox.
- `test/klass_hero/event_consumer_wiring_test.exs` already guards the registry
  line, bidirectionally, so a consumer that declares an event it is not routed
  fails the build.
- The `:email` queue went from concurrency 1 to 5 to absorb broadcast fan-out.
  Concurrency is not the upstream ceiling, so every worker on that queue also
  went to `max_attempts: 5`: at 3, a sustained 429 burst can spend the whole
  budget on backoff and **discard** a real email rather than delay it. Those two
  numbers are one decision and are asserted together in
  `test/klass_hero/email_queue_capacity_test.exs`.
- Job args carry ids only. An address in `oban_jobs.args` outlives the send by
  the Pruner's retention, and one changed between enqueue and delivery would
  send to the old mailbox. The worker re-checks the preference and fetches the
  address itself.
- Notification emails carry a link, never content. For #1071 this is a
  deliberate omission: the `message_sent` payload does include `content`.

## Alternatives considered

**Preference on `Family.ParentProfile`**, as #1071 originally specified. Its
`notification_preferences` map is dead scaffolding — nullable `jsonb`, no
default, no key schema, cast wholesale — and `KlassHero.Family` has no update
path at all, so that route had to invent a Family mutation anyway. It would also
have made the feature structurally parent-only while the toggle sits beside
`locale`, a user-level column, in the same settings card.

**A `Notifications` bounded context.** Rejected: `domain-architecture.md` is
explicit that "service"-style catch-alls sort modules by having no category, and
the existing convention is that consumers live in the context that consumes the
event.
