# Support Inbox lives inside the Messaging context

The Support Inbox — external email from the public, received via the Resend webhook and triaged by Admins — is implemented inside the Messaging bounded context (`lib/klass_hero/messaging/`), even though it shares no rows, associations, or use cases with in-app Conversations and Messages. Its `InboundEmail` and `EmailReply` entities reference only `users` (the Admin who reads or replies); they never touch `conversations` or `messages`.

It is co-located rather than extracted because, at ~2 passive entities, a dedicated context buys nothing: a separate context module, Boundary declaration, DI wiring, and config envelope would all be overhead with no coupling to justify them. "Messaging" is the nearest existing home — both deal with communication — so the inbox was written there.

The trade-off is conceptual honesty: a future reader sees email handling inside a context named for in-app conversations and reasonably asks why. The two subsystems are deliberately distinct channels with different actor populations — Conversations require platform Users, whereas an Inbound Email can come from any external party with no account — so the shared context is a co-location of convenience, not a domain relationship.

## When to extract into a Support context

Revisit the split when the inbox stops being two passive tables and grows its own domain. Concretely, any of:

- Ticket-like workflow: assignment/ownership, SLA or escalation, or a status lifecycle richer than `unread → read → archived`.
- A second external inbound channel (e.g. SMS, WhatsApp) joins email under the same triage surface.

Extraction is **not** triggered by new actors: non-Admin users will never get an inbox — they communicate through in-app Messaging by design — so the Admin-only, public-inbound shape is permanent.

Because the inbox is already fully decoupled (no shared schema or use case), the eventual move is close to mechanical: relocate the files, give the new context its own Boundary and config key, and point the `admin/emails` surface at it.

## Consequences

- The Messaging context's Boundary `deps` and public API carry inbox concerns that have nothing to do with Conversations; reviewers should not infer a relationship from the shared module.
- The pending rename (`EmailsLive`/`admin/emails` → a Support-Inbox-named surface) and the context extraction are independent — the canonical name can be fixed without moving contexts.
- No cross-context events flow from inbound mail today; if that need appears, treat it as an extraction signal, not as new wiring inside Messaging.
