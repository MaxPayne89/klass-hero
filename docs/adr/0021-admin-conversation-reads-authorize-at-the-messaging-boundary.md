# Admin conversation reads authorize at the Messaging boundary

**Date:** 2026-08-25 · **Issue:** #744

A platform admin may read any conversation. That permission is granted inside
`KlassHero.Messaging`, against the caller's `Accounts.Scope`, by a named gate:

```elixir
Messaging.monitor_conversations(scope, opts)
Messaging.get_monitored_conversation(scope, conversation_id, opts)
```

Both fail closed with `{:error, :unauthorized}` unless `scope.user.is_admin`. The
router's `:require_admin` on_mount stays, as defence in depth rather than as the
guarantee.

## Why not the router alone

Every other admin surface in this app authorizes at the router and nowhere else.
`EmailsLive` calls `Messaging.list_inbound_emails/1`, which takes no scope; the
Backpex resources go straight to Ecto. That is a defensible trade for inbound
support mail and for admin dropdown labels.

Conversations are different in kind. They are private correspondence between
parents and the people looking after their children, and Messaging gates *every
other* read of them on a participant row (`Authorization.verify_participant/2`).
An ungated `list_all_conversations/1` sitting in that same facade would be an IDOR
primitive: correct as long as the only caller is a LiveView behind `:require_admin`,
and wrong the first time anything else calls it. This repository has already paid
for that pattern seven times (#1125, #1373, #1477 among them), and ADR-0017 records
the same lesson on the write side — a guard that lives in one of four callers is
not a guard.

So the gate moves to where the data is, and the web layer keeps its own check.

## One clause, not a fall-through

`Participation.SessionAuthorization.authorize/2` resolves an actor through an
ordered table — provider, then staff, then admin — because there, admin is the
broadest rule you reach after narrower ones fail, and the resolved role selects
*behaviour* (an admin correction demands a written reason; a provider's does not).

`Messaging.Authorization.authorize_admin/1` is a single clause instead:

```elixir
def authorize_admin(%Scope{user: %{is_admin: true}}), do: :ok
def authorize_admin(%Scope{} = scope), do: {:error, :unauthorized}
```

Nobody is *narrowly* authorized to read every conversation on the platform, so
there is nothing to fall through from. Modelling it as a table would imply a
precedence that does not exist.

`is_admin` is derived, not declared: it lives on the user row and is absent from
`registration_changeset`'s cast list, so no request can grant it to itself.

## Authorization runs before the id is read

`GetConversation.execute/3` fetches the conversation *first* and checks the
participant row second, so `{:error, :not_found}` and `{:error, :not_participant}`
are distinguishable to a caller — the enumeration oracle ADR-0017 warns about. That
is pre-existing and is not fixed here; collapsing it would change the flash contract
on all six parent/provider/staff message surfaces.

The admin path does not inherit it. `authorize_admin/1` is the first thing both use
cases call, so a non-admin gets `:unauthorized` whatever id they supply. Past the
gate an admin has blanket visibility, so a later `:not_found` discloses nothing they
were not already entitled to know.

## A parallel path, not a widened gate

The alternative was to generalize `verify_participant/2` into a scope-taking
fall-through so `get_conversation/3` would serve admins unchanged. It was rejected:
that function has three callers, and two of them — `SendMessage` and `MarkAsRead` —
must **not** gain an admin branch. "One gate" would immediately have become "one
gate with an exception list", on the child-safety read path, while also migrating
six LiveViews from `user_id` to `%Scope{}`.

Keeping the paths separate makes the write-side property checkable instead of
argued: `SendMessage` and `MarkAsRead` never call `authorize_admin/1`, and a test in
`get_monitored_conversation_test.exs` pins that a non-participant admin still gets
`{:error, :not_participant}` from `send_message/4`.

## Reading marks nothing

`GetMonitoredConversation.execute/3` has **no `:mark_as_read` option at all**, where
`GetConversation.execute/3` has one that can be passed by mistake.

This is not fastidiousness. `Participant.last_read_at` is read by three independent
unread implementations — `ConversationSummary.unread_count` behind the nav badge,
`ConversationQueries.total_unread_count/1`, and the `ConversationSummaries`
projection, which re-reads participant rows and routes on whether `last_read_at` is
nil or dated. An admin view that touched it would silently move somebody else's
unread count. Omitting the option makes that unexpressible rather than merely
unused.

For the same reason the listing reads the write-side `conversations` table and not
`conversation_summaries`: that projection is keyed `(conversation_id, user_id)`, so
an admin has no row in it, and reading it anyway would return one row per
participant per conversation.

## The access trail

There is no durable admin-access log, here or anywhere in the app —
`KlassHeroWeb.AuditInfo` is waiver-specific, and `IncidentLive` and
`UndeliveredEventLive` both keep no record of which admin viewed what.

Monitoring reads emit an OpenTelemetry span carrying `messaging.monitoring.admin_id`
and `messaging.monitoring.conversation_id`, plus a `Logger.info` line on the thread
read. That gives a queryable trail with no new infrastructure, bounded by Honeycomb
retention.

That is weaker than a table, and weaker than ADR-0017's admin branch, which demands
a written reason for an attendance correction. It is a deliberate first cut: if a
subject access request ever has to answer "who read my messages", the span retention
window is the limit, and a durable log becomes the follow-up.

## Disclosure is part of the feature

Monitoring ships with #745 — a `:system` message in every provider-context
conversation — and with a "Platform Administrators" clause in the privacy policy,
whose Data Sharing section previously named only Program Providers and Payment
Processors.

The capability and its disclosure are one change. Shipping the read path alone would
create a processing activity disclosed nowhere.

## Consequences

- Messaging now has **three** read gates (amended — see below). `verify_participant/2`
  guards everything participant-scoped; `authorize_admin/1` guards platform
  monitoring; `authorize_provider_owner/1` guards a provider owner reading their own
  business's threads. Nothing else may use any of them without a further amendment.
- `/admin/messages` is the first admin surface whose authorization lives in a
  context. The others are unchanged; this is not a call to migrate them.
- The enumeration oracle in `GetConversation.execute/3` remains open; filed as #1515.

## Amended: provider owners (#746)

**Date:** 2026-08-25

A provider owner may read conversations their business owns but that they are not a
participant of — chiefly the threads their staff conduct with parents. Granted inside
`KlassHero.Messaging` by a second named gate:

```elixir
Messaging.list_staff_conversations(scope, opts)
Messaging.get_staff_conversation(scope, conversation_id, opts)
```

This amendment exists because the section above reserved `authorize_admin/1` to
monitoring and required an ADR amendment before any further non-participant read. The
original is not superseded; only the two-gate count above changes.

### Owner-only, and pointedly not staff

```elixir
def authorize_provider_owner(%Scope{provider: %{id: id}}), do: {:ok, id}
def authorize_provider_owner(%Scope{} = scope), do: {:error, :unauthorized}
```

One clause, for the reason `authorize_admin/1` is one clause: nobody is *narrowly*
entitled to read a whole business's correspondence, so there is nothing to fall
through from.

The tempting reuse was `Authorization.resolve_acting_provider/2`, which already binds
a scope to a provider. It is the wrong function here. That one accepts a staff scope
on purpose — a staff member carries no `scope.provider`, so the write path has to
resolve their employer from a caller-supplied hint. Honouring that hint on this read
would let one staff member read their colleagues' private threads with parents, which
is the opposite of what this gate is for. The provider can only come from
`scope.provider`.

### Why this gate returns an id where the admin gate returns `:ok`

`is_admin` grants blanket visibility: past that gate, every conversation is fair game,
which is why `GetMonitoredConversation` can fetch by id alone. Provider ownership
grants nothing of the sort — it proves the scope owns *a* provider, never that it owns
*this* conversation. So the gate hands back the provider id, and it is the read
predicate:

```elixir
ConversationQueries.base() |> by_id(id) |> by_provider(provider_id) |> Repo.one()
```

Both predicates ride in one query, so "belongs to another business" and "does not
exist" collapse into the same `{:error, :not_found}` at no extra cost. Without that
second predicate a pasted UUID would read a competitor's threads.

### The predicate is `provider_id`, not a staff join

#746 proposed listing conversations whose *participants* are active staff members.
Rejected: `Messaging.get_provider_staff_user_ids/1` already documents that
ever-employed staff lists "must never gate access", and its active-only sibling is the
"may act now" gate. Keying an oversight view on *current* employment would hide the
threads an owner remains accountable for the moment a staffer is deactivated.

Every conversation already carries `provider_id` as a required field, bound to the
acting scope at write time. The ownership fact is stored, not derived.

Threads the owner already participates in are excluded via
`where_user_is_not_participant/2` — those render in their own inbox, and listing them
twice across two tabs helps nobody.

### Read-only, and marking nothing

`GetStaffConversation` has no `:mark_as_read` option, for the reason recorded above:
`last_read_at` feeds three independent unread counters, and an owner must not move a
parent's or a staff member's. `SendMessage` and `MarkAsRead` gained no owner branch,
and a test in `get_staff_conversation_test.exs` pins that a non-participant owner
still gets `{:error, :not_participant}` from `send_message/4`.

The access trail is the same shape as monitoring's: an OpenTelemetry span carrying
`messaging.staff_conversations.owner_id` and `…conversation_id`, plus a `Logger.info`
on each thread read. Still no durable table.

### Disclosure, inverted

Monitoring shipped its disclosure with the capability. Here the disclosure shipped
*first*: the notice added in #1516 already reads "may be reviewed by the activity
provider and by Klass Hero staff", which was true of Klass Hero staff and not yet true
of the provider. This change makes the shipped sentence honest, and adds the matching
clause to the privacy policy's **Program Providers** section, which previously covered
only children's names, safety information and session notes.
