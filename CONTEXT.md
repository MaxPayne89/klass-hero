# Klass Hero

The domain glossary for Klass Hero — a platform for afterschool activities, camps, and class trips that connects parents, providers, and instructors. This file defines the language we use; it is not a spec.

## The Offering

**Program**:
A bookable offering a Provider lists for children to attend. Today a single `Program` entity serves all offering kinds, distinguished by a subject **Category**. It carries a recurring schedule (the days/times it meets) and a **Registration Period**.
_Avoid_: Activity, Class, Course, Offering, Listing

**Subtitle**:
An optional one-line hook a **Provider** writes under a **Program**'s title — the
secondary detail that makes it click for a parent ("For beginners, no experience
needed", "Small groups, ages 6-9"). Display only: nothing reads it, filters on it,
or decides anything from it. A Program without one shows its title alone.
_Avoid_: Tagline, Summary, Short description (it is not a shortened **Description**,
which stays the full prose); and never the offering's *kind* — "Camp", "Weekly
class" — which is format information that **Category** already refuses.

**Category**:
The *subject* of a Program — what it is about. Current values: `sports`, `arts`, `music`, `education`, `life-skills`. This is one axis only and must not carry format/kind information.
_Avoid_: Type, Kind, Tag

**Registration Period**:
The window during which parents may enrol in a Program. When unbounded, registration is "always open".
_Avoid_: Enrolment window, Signup period, Booking window

**Closed Program**:
A **Program** whose end date passed longer ago than the access grace window (14 days). Its assigned **Staff Members** lose it: no sessions, no roster, no check-in or correction, no broadcast — it appears on their dashboard as a read-only "Completed" entry and nothing more. The **Provider** who owns it and an **Admin** are unaffected, because they still have to correct what happened. Derived from the end date, never stored, so a Program is never "closed" by anyone's action; it simply has been over for long enough. See [ADR-0019](adr/0019-closed-programs-revoke-staff-access.md).
_Avoid_: Archived (that is a **Conversation**), Completed (that is a **Session**'s lifecycle), Expired, Ended (the date fact, not its consequence)

**Price**:
What a **Program** costs a parent, always **gross** — the final amount payable, VAT included whatever the rate turns out to be. A Provider entering "100" means the parent pays €100. Net and VAT are *derived* from it, never the other way round.
_Avoid_: Net price, Fee (reserved for the platform's success-based fee), Cost

**Free Program**:
A **Program** whose **Price** is zero. Distinct from one that has *no* price yet, which is simply incomplete — a Provider who has not filled the field in has said nothing about money, where a zero says something definite: no **Payment** exists for this Program (see **Payment**). Every parent-facing surface says "Free" rather than "€0.00", because a zero amount reads as a formatting accident. The three states are named in code as `:free`, `:unset` and `{:priced, amount}`.
_Avoid_: No Cost ("Cost" is not our word — see **Price**), Zero-price, Gratis, Complimentary

## Scheduling

**Session**:
A single dated occurrence of a Program (a date plus start/end time) that children attend and staff run. The Program attachment is implicit — we just say "Session", never "Program Session". Has its own lifecycle: `scheduled → in_progress → completed`, or `cancelled`. Who may drive that lifecycle is decided inside the Participation context, from the actor's Scope, in the same Provider → Staff Member → admin order as **Attendance** — see [ADR-0017](docs/adr/0017-attendance-writes-authorize-at-the-context-boundary.md). Completing a Session marks every still-`registered` **Participation Record** `absent`, which is why it is a guarded write and not a display change.
_Avoid_: Class, Meeting, Occurrence, Program Session; and never reuse "Session" for the authentication session

## Enrollment & Attendance

**Enrollment**:
A child's signup to a **Program** — the program-level commitment, made once. Feeds the **Roster** of every Session in that Program. Parents "book" a Program; the record that results is an Enrollment.
_Avoid_: Registration, Signup; and "Booking" as a domain *noun* ("Book" is fine as a front-of-house verb only — see flagged ambiguities)

**Enrollment Policy**:
A **Program**'s optional minimum and maximum **Enrollment** counts. The maximum is the *cap* — the bound the Enrollment context enforces when a place is booked; a Program with no maximum is *uncapped*, and anyone may book. The minimum is a viability threshold only, enforced nowhere at booking time. Removing a cap from a Program that already has active Enrollments is a deliberate act the provider must acknowledge — it cannot happen as a side effect of an edit.
_Avoid_: Capacity as a noun for the row itself ("the capacity" is the number), Limit, Quota

**Roster**:
The set of children expected at a given **Session**, seeded from the Program's active **Enrollments**. A roster belongs to one Session.
_Avoid_: Attendance list, Class list, Sign-in sheet

**Participation Record**:
One child's row on one Session's Roster, tracking presence through `registered → checked_in → checked_out`, or `absent`. `registered` here means "on the roster, not yet arrived" — it is not the **Enrollment**.
_Avoid_: Attendance record, Booking

**Attendance**:
The act and result of checking a child in and out of a **Session** (the state changes recorded on a **Participation Record**). Who may record it is decided inside the Participation context, from the actor's Scope, in the order Provider → Staff Member → admin — see [ADR-0017](docs/adr/0017-attendance-writes-authorize-at-the-context-boundary.md). The Staff Member's authority comes from a **Program Staff Assignment**, never from their **Specialties**.
_Avoid_: Presence, Sign-in

**Absence Reason**:
Why a child was marked absent, in the Instructor's own words ("mum called, off sick"). Operational and immediate — it tells whoever is running the Session where the child is, and it is deliberately **not** a **Session Note**: a note is feedback about the child that the **Parent** must approve before it is shared, and nobody should have to approve a dispatch note. Recorded against the **Attendance Transition** that made the child absent, not stored on the Participation Record, so a child marked absent twice keeps both reasons. Absent only when someone chose it: completing a Session sweeps every still-`registered` child to `absent` with no reason and no actor, which is how an automatic absence is told from a deliberate one.
_Avoid_: Absence Note, Excuse, Sick Note

**Attendance Transition**:
One recorded change to a **Participation Record**'s state — from and to, by whom, when, and why. Every attendance write appends one, so the roster's history survives the record only holding its latest state. A transition with no actor was made by the system, not a person.
_Avoid_: Attendance Event ("Event" means an integration event here), Audit Log entry

## Payments & Invoicing

**Invoice**:
An immutable, numbered record of money owed or paid for one **Enrollment**, issued by Klass Hero. Append-only: it is never edited after issue, and a correction is a new Invoice, not a change to the old one. Comes in three kinds — a **Rechnung** to the **Parent**, a **Gutschrift** to the **Provider**, and a **Storno** reversing either. One concept rather than three, because German law treats a Gutschrift as an invoice issued by the recipient of the supply (§14 Abs. 2 S. 2 UStG).
_Avoid_: Document (that's a **Verification Document**), Receipt, Bill, Booking invoice ("Booking" is not a domain noun)

**Rechnung**:
The **Invoice** kind issued by Klass Hero to a **Parent** for an **Enrollment**. Klass Hero's own VAT treatment governs it. The German term is kept because the document is German and consumer-facing.
_Avoid_: Parent invoice, Receipt

**Gutschrift**:
The **Invoice** kind issued by Klass Hero to a **Provider**, self-billing for the provider's supply. The **Provider**'s own VAT status governs it, and issuing it requires the provider's prior agreement.
_Avoid_: Credit note (means something else in English), Payout statement, Self-bill

**Storno**:
The **Invoice** kind that reverses a **Rechnung** or a **Gutschrift** after a cancellation or refund. Never mutates the invoice it reverses.
_Avoid_: Cancellation (that's the **Enrollment** state change that may cause a Storno), Credit note, Refund (the money movement, not the document)

**Payment**:
The **Parent**'s money movement into Klass Hero for one **Enrollment**. Two-phase: the money is *held* when the parent books and only *taken* once the **Provider** accepts. Taking it is what confirms the **Enrollment** — neither the parent submitting the form nor the provider accepting does so alone. A held Payment that is never taken lapses and no money moves. Only programs with a **Price** above zero have one.
_Avoid_: Charge (the processor's term), Transaction, Booking payment ("Booking" is not a domain noun)

**Transfer**:
The movement of a **Provider**'s share from Klass Hero to that provider's connected account. Held back until the **Program** begins, so that Klass Hero — not the provider — holds the money while a booking can still be cancelled. Separate from the **Payment**, later than it, and able to fail on its own.
_Avoid_: Payout (that is the next leg), Settlement, Disbursement

**Payout**:
The movement of money from a **Provider**'s connected account to their bank account. Scheduled and executed by the payment processor — Klass Hero sets the schedule and may hold it, but does not move the money itself.
_Avoid_: Transfer (that is the previous leg), Withdrawal

**Refund**:
The return of a **Payment** to the **Parent** after an **Enrollment** is cancelled. Always the full amount while the **Program** has not yet begun, which is the only window Klass Hero supports — because Klass Hero still holds the money then, a Refund is never reclaimed from the **Provider**. Recorded by a **Storno**.
_Avoid_: Reversal, Chargeback (that is the parent's bank acting against us, not us refunding), Cancellation (the **Enrollment** state change that causes it)

**Processing Fee**:
The payment processor's actual cost on one **Enrollment**'s **Payment**, passed through so that Klass Hero nets zero on it. It is a recovered cost, **not revenue**, and deliberately not the **Success Fee**. Deducted from what the **Provider** receives, so a provider's payout is less than the **Price** by this amount.
_Avoid_: Commission (deleted with provider tiers, ADR-0004), Platform fee, Application fee (that's the processor's API term), Service charge

**Success Fee**:
The planned share of a **Provider**'s platform income that Klass Hero will earn ("we earn when you earn"). Not built and not modelled — see [ADR-0004](adr/0004-provider-tiers-removed-success-fee-planned.md). Distinct from the **Processing Fee**: one is Klass Hero's margin, the other is a cost recovered at zero margin. Do not let code, copy, or invoices blur them.
_Avoid_: Commission, Tier rate, Take rate

## Providers & Staff

**Provider**:
The business or organisation that lists **Programs** and employs **Staff Members**. Parents see the Provider as the entity behind a Program. Modelled as the `ProviderProfile` struct (DB table `providers`); "Provider" and "ProviderProfile" are the same thing — the profile *is* the provider, and `provider_id`/`provider_profile_id` point at it interchangeably.
Provider-hood is **always a deliberate act** by the person themselves — either self-registering as a provider, or a **Staff Member** explicitly *upgrading* ("do my own thing"). It is **never** conferred automatically by being hired, and an **Admin** never creates a Provider on someone's behalf. A person (**User**) can be a Provider *and* a Staff Member at once (e.g. a founder who still teaches, or a staff member running something on the side) — these are independent **personas**, not the same record. A Provider who wants to teach their own Programs must deliberately add themselves as a **Staff Member** of their own business (self-staffing); a pure-business Provider never becomes a Staff Member.
_Avoid_: Vendor, Merchant, Business, Partner, Organiser

**Staff Member**:
An **employment link** between a person and one **Provider** — *not* the person themselves. The person is the **User**; the Staff Member is their record of working *for that one Provider*, carrying a **Role**, qualifications, pay rate and a display copy of name/bio/headshot. One person (User) may hold *several* Staff Member records, one per employing Provider. May be invited to claim a **User** account, and may be assigned to one or more **Programs** of that Provider.
_Avoid_: Employee, Team member, Worker; and treating a Staff Member as the person (the **User** is the person)

**Instructor**:
The lead **Staff Member** responsible for running a Program — the "boss" for that Program (or for a specific **Session**). Exactly one Instructor leads, even though several Staff Members may be assigned alongside them. In the Program Catalog this person also appears as a read-only display copy.
_Avoid_: Teacher, Coach, Trainer (those are **Roles**, not the lead responsibility)

**Role**:
A **Staff Member**'s specific job title — freeform text such as "Coach" or "Teacher". Distinct from **Instructor**, which is the lead responsibility for a Program/Session, not a title.
_Avoid_: Position, Title, Type

**Deactivation**:
Ending a **Staff Member**'s employment link — they no longer work for that **Provider**. Reversible (*reactivation*), and deliberately narrow: any **Instructor** role they held is cleared and an outstanding invitation is revoked, but their **Program Staff Assignments** and conversation membership survive, because unassigning would destroy access that reactivation cannot give back. Reactivation restores only the employment: the Instructor role and the invitation stay gone.
Distinct from two neighbours that land on the same `active` column: **offboarding** (below) and **erasure** (GDPR, which offboards *and* scrubs PII). Deactivation alone says nothing about why.
_Avoid_: Disable, Archive, Soft-delete, Suspend, Terminate

**Offboarding**:
**Deactivation** plus the roster teardown: every live **Program Staff Assignment** is retired, which is what removes the person from those Programs' **Conversations**. This is what the Team tab's "Remove from team" does, and what **erasure** does before scrubbing. The employment can be reinstated, but the assignments cannot — reinstating gives back an employee with no Programs, so re-assign deliberately.
The distinction from deactivation is the whole point: deactivation keeps assignments alive so a reversible pause does not destroy conversation access; offboarding is the person leaving, so the access has to go.
_Avoid_: Remove, Delete, Fire (removal now means the erase below)

**Removal (erase)**:
Destroying a **Staff Member** row outright. Legal only for a row that never became anything — no linked **User**, no invitation ever sent, no **Program Staff Assignment** ever created — i.e. a roster entry typed in by mistake. Anything else is **offboarded** instead, because events and audit records name that `staff_member_id` and deleting the row would leave them pointing at nothing.
_Avoid_: using this word for an employee leaving — that is **offboarding**

**Program Staff Assignment**:
The link recording that a **Staff Member** works on a **Program**. Many Staff Members may be assigned to one Program because a class can need several people. Survives the Staff Member's **deactivation**, but not their **offboarding**.
This is the **only** thing that *grants* a Staff Member access to a Program — their dashboard, their sessions, participation, and broadcast compose all read it. A **Specialty** never grants access (#1323). Access additionally *lapses* once the Program becomes a **Closed Program** (#1082): the assignment says who, closure says whether it still counts.
_Avoid_: Membership, Posting

**Specialty**:
A descriptive marker of what a **Staff Member** is good at, drawn from the **Category** list and shown on their team card. Editorial, not operational: it says "Maria coaches sports", never "Maria may open this Program". Access is a **Program Staff Assignment** and nothing else.
Stored in the `staff_members.tags` column, which is why the name misleads — the column predates the distinction and the form has always labelled it "Specialties". Until #1323 the four staff surfaces scoped by matching this against `program.category`, with an empty list silently meaning *every* Program; that made a description into an authorization rule, and made check-in on a child's roster depend on a category string.
_Avoid_: Tag, Skill, Assignment, and any phrasing that implies it confers access

## Families & Accounts

**User**:
An authentication identity in the Accounts context — email, password, `intended_roles` (`:parent | :provider | :staff`). The **User is the person**: a person logs in as one User and may hold *several* domain **personas** at once — **Parent**, one or more **Staff Member** records, and/or a **Provider** — each living in another context and linking back by a correlation id, not a foreign key. `intended_roles` is the signup-intent / landing hint and an eventual-consistency bridge (personas are created asynchronously); the **authority for authorization is persona existence** (`Scope.provider?`, `Scope.staff?`, …), kept in step by appending the matching role atom whenever a persona is gained.
_Avoid_: Account, Login, Member

**Admin**:
A platform operator (not a **Parent** or **Provider**) who reviews **Verification Documents** and **Incident Reports**, approves pending **Enrollments**, and may read any **Conversation** under **Monitoring**. The reviewer behind `reviewed_by_id`.
_Avoid_: Moderator, Superuser, Staff (Staff belongs to a Provider)

**Monitoring**:
An **Admin**'s read-only access to any **Conversation**, for safety, abuse prevention and compliance. Deliberately *not* moderation: monitoring reads, and has no power to write, delete or intervene in a thread. An Admin monitoring a Conversation does not become a **Participant** — no membership is created, and no read receipt moves — so monitoring is invisible to participant counts and unread badges. Disclosed to participants by a **System Message** in every provider-context Conversation.
_Avoid_: Moderation (that implies intervention), Surveillance, Oversight, Audit (that names the trail, not the act)

**Parent**:
The account-holding persona who manages **Children**, books **Programs**, and pays. A Parent is a **Guardian** who holds a **User** account.
_Avoid_: Customer, Buyer, Family (Family is the context, not the person)

**Guardian**:
Any adult with a custodial relationship to a **Child**. A Child has one *or more* Guardians (e.g. two parents plus a grandparent); not every Guardian necessarily holds an account. Multiple guardians per child is intended, not incidental.
_Avoid_: Parent (reserve that for the account-holding role), Caregiver, Custodian

**Child**:
A young person who attends **Programs**, belonging to one or more **Guardians**. The person a **Parent** enrols and a **Roster** tracks.
_Avoid_: Kid, Student, Participant, Attendee

## Messaging

**Conversation**:
A messaging thread always anchored to a **Provider** (and optionally a **Program**). Comes in two kinds — a **Direct Conversation** or a **Broadcast** — and can be **Archived**, after which it is kept until a **Retention** deadline and then purged.
_Avoid_: Thread, Chat, Channel

**Direct Conversation** (`direct`):
A thread between specific **Users** — typically a **Parent** and the **Provider**'s staff — whose membership is an explicit set of **Participants** who join and leave.
_Avoid_: DM, Private message

**Broadcast** (`program_broadcast`):
A Provider's one-to-many announcement thread scoped to a single **Program**. At most one active Broadcast exists per Program. Its audience is *derived*, not hand-added: the **Parents**/guardians of the children **Enrolled** in that Program, plus the Program's assigned **Staff Members**. Recipients are not **Participants**.
_Avoid_: Announcement, Bulletin, Newsletter, Channel

**Message**:
A single entry within a **Conversation** (Direct or Broadcast). Usually typed by a **User**, but may instead be a **System Message**; it may carry **Attachments** (and a Message can be attachments-only, with no text). A sender may delete their own Message — a *soft* delete that hides it but keeps the row — distinct from the **Retention** purge that later hard-deletes the whole thread.

**System Message**:
A **Message** the platform generates rather than a person types — for example a marker recorded in a **Broadcast**. Shares the Message timeline but is not user-authored.
_Avoid_: System Note (that risks colliding with **Session Note**), Notification, Event

**Attachment**:
A file attached to a **Message** — a photo or document with a filename, content type and size. Immutable once created; never edited. Deleted with its Message, and purged from storage when the **Conversation** passes its **Retention Period**.
_Avoid_: Upload, File, Media, Document (that's a **Verification Document**, unrelated)

**Participant** (Messaging):
A **User**'s membership in a **Direct Conversation** — tracks join/leave and read receipts. Applies to Direct Conversations only; a **Broadcast** has a derived audience, not Participants. This is the *only* meaning of "Participant" in the system; it is **not** a child attending a Session. An **Admin** reading a Conversation under **Monitoring** is not a Participant either: reading it seats nobody and moves no read receipt.
_Avoid_: using "Participant" for a child on a **Roster** (that's a **Participation Record**), or for a **Broadcast** recipient

**Archival**:
The automatic retirement of a **Conversation** once its **Program** has ended (after a grace window). Archiving starts the **Retention Period**; it deletes nothing yet. A **Direct Conversation** with no Program is never archived — it lives indefinitely.
_Avoid_: Delete, Close, Hide

**Retention Period**:
The window an archived **Conversation** (with its **Messages** and **Attachments**) is kept before being *purged* — a permanent hard delete, including attachment files in storage. Not recoverable. Distinct from the **Registration Period** on a Program.
_Avoid_: Expiry, TTL; "purge" is the destructive end-state, not ordinary message deletion

## Support Inbox

A communication **channel** separate from in-app **Messaging** — external email handled by **Admins**, with no link to **Conversations**, **Parents** or **Providers**. Deliberately distinct; not merged with in-app messaging. "Support Inbox" is the canonical name; the code still says "Admin Inbox" / `emails` (`admin/emails`, `EmailsLive`) — a pending rename.
_Avoid_: Admin Inbox, Emails (channel name), Tickets queue

**Inbound Email**:
An email received from outside the platform via the Resend webhook, triaged by an **Admin** (`unread → read → archived`). The sender is *any external party* — typically a prospect or a member of the public with a question, who need not be a platform **User**. This is why the channel shares no model with **Conversations** (which require Users). Body content is fetched asynchronously after the metadata arrives.
_Avoid_: Message (in-app only), Ticket

**Email Reply**:
An **Admin**'s reply to an **Inbound Email**, sent from the admin dashboard (`sending → sent → failed`).
_Avoid_: Message, Response

## Safeguarding & Feedback

**Incident Report**:
A formal safeguarding/operational record of an event during a **Program** or a **Session** — injury, safety concern, property damage, policy violation, or a serious behavioural incident. Filed by a Provider's staff, severity-rated (`low`–`critical`), routed to admins, and never parent-approved.
_Avoid_: Note, Complaint, unqualified "Report"

**Session Note**:
Routine per-child feedback from the **Instructor** about one **Child** at one **Session** (often positive, e.g. "very engaged today"). The **Parent** must approve it before it is shared; a rejected note can be revised. Attached to the child's **Participation Record**.
_Avoid_: Behavioral Note (retired in #924), Feedback, Review, Comment

## Trust & Compliance

**Consent**:
A **Guardian**'s recorded permission for a specific **Child** and a specific purpose — `photo_marketing`, `photo_social_media`, `medical`, `activity_participation` (currently `participation` in code — rename pending), or `provider_data_sharing`. Append-only for audit: re-granting or withdrawing adds a new record; the live state is the latest non-withdrawn one.
_Avoid_: Permission, Agreement, Opt-in

**Verification Document**:
A document a **Provider** uploads for **Admin** review to establish trust — `business_registration`, `insurance_certificate`, `id_document`, `tax_certificate`. Lifecycle `pending → approved / rejected`.
_Avoid_: Credential, Proof; "Certificate"/"Registration" name *document types*, not the concept

**Vetting**:
The process that gates whether a **Provider** is trusted enough to be listed. A composable, ordered step engine (not a single boolean) selected by the provider's entity type. See [ADR-0008](adr/0008-provider-vetting-is-a-composable-step-engine.md) and `docs/6-step-verification-process.md`.
_Avoid_: Onboarding (broader), Approval (an outcome, not the process)

**Vetting Case**:
The aggregate holding one **Provider**'s vetting: a `not_started → in_progress → verified` lifecycle over a frozen set of **Verification Step**s. A provider is verified exactly when every step is approved; that transition emits the frozen `provider_verified` fact other contexts consume.

**Track**:
The ordered set of **Verification Step**s a provider must complete, chosen by entity type. The `:individual` track is the six-step spine (identity, experience, background, video, safeguarding, community agreement); `:business` is a follow-up. Track composition lives in code, not data.

**Verification Step**:
One requirement inside a **Vetting Case** — `not_started → submitted → approved / rejected`. Completed via one of three evidence kinds: a **Verification Document** (admin-reviewed), an **Identity Verification** (Stripe), or a **Signed Agreement** (auto-approved). A rejection resets the step and its transitive dependents.

**Identity Verification**:
The outcome of one Stripe Identity session run against a person, backing the identity **Verification Step**. Append-only; stores only the session id and pass/fail outcome — never the date of birth or document images. The webhook is the source of truth; the age gate is fail-closed (18+). See [ADR-0009](adr/0009-stripe-identity-step-webhook-is-truth-age-gate-fail-closed.md).

**Signed Agreement** (incl. **Community Agreement**):
A **Provider**'s explicit, recorded consent to a versioned agreement, backing an auto-approving **Verification Step** (no admin review). The individual track's final step is the **Community Agreement** to the versioned Community Guidelines. Append-only: a re-agreement (e.g. after a version bump) is a fresh record, so consent history stays auditable.
_Avoid_: Consent (reserved for **Guardian** permissions above)

**Staff Attestation**:
A `:business` **Provider**'s final vetting step (B5): a versioned **Signed Agreement** (`kind: :staff_attestation`) in which the **Responsible Person** declares, on the business's authority, that every instructor has been background-checked to the German legal standard (erweitertes Führungszeugnis, § 72a SGB VIII), and accepts the associated indemnity and penalty terms. Auto-approves on signing. **Data-minimisation is definitional**: Klass Hero stores only the contractual declaration (who signed, when, which version) — never certificate contents or criminal-record data — which keeps the platform outside GDPR Art. 10 scope. Distinct from an **Identity Verification**: no third party, no file, a pure recorded commitment.
_Avoid_: Background check (that is the instructor-level act the business attests *to*, not held by Klass Hero); Certificate

**Responsible Person**:
On a `:business` **Provider**, the named owner/director legally accountable for the business on Klass Hero. Carried as a value on the **Provider** (name + role), not a separate entity. **Vetting** is tied to this person, not the business entity: the **Identity Verification** (B1) runs against them, and the business **Community Agreement** and **Staff Attestation** are signed on their authority. Changing the responsible person is an explicit act — a dedicated command is the *only* mutator, and it (not an incidental profile edit) resets the identity step, cascading to the agreements that require it. A typo correction is not a change.
_Avoid_: Owner, Director (those are *roles* the person may hold, not the concept); Contact

## Parked (not modelled)

**Referral**:
Not a modelled concept yet. Only a code-format generator exists (`{FIRST_NAME}-{LOCATION}-{YEAR}`); there is no stored referral, claim, or reward. Parked — define this term only if/when the feature is built.

## Example dialogue

> **Dev:** A Parent just booked the Monday football class for two of their kids. What did we actually create?
>
> **Domain expert:** Two **Enrollments** — one per **Child** — against that **Program**. "Book" is just what the Parent does in the UI; the records are Enrollments.
>
> **Dev:** Both kids are the same Parent's, but I see three adults linked to one of them.
>
> **Domain expert:** Right — a **Child** can have several **Guardians**. Only the **Parent** (the Guardian with a **User** account) does the booking and pays, but the others are still Guardians.
>
> **Dev:** When does the football actually happen?
>
> **Domain expert:** Each occurrence is a **Session**. When a Session is created, its **Roster** is seeded from the Program's active Enrollments — one **Participation Record** per enrolled Child, starting as `registered`.
>
> **Dev:** And on the day?
>
> **Domain expert:** The **Instructor** — the **Staff Member** leading that Program — checks each child in and out. That's **Attendance**, recorded on the Participation Record. Other Staff Members can be assigned too if the class needs more hands.
>
> **Dev:** The Parent messaged the Provider about a pickup change — is that child now a "participant"?
>
> **Domain expert:** No. In that **Conversation** the Parent is a **Participant**. The child on the Roster is never called a participant — that word is messaging-only.

## Flagged ambiguities

**Offering kind is overloaded onto Category.**
The persisted category list currently mixes two axes: *subject* (`sports`, `arts`, `music`, `education`, `life-skills`) and *format/kind* (`camps`, `workshops`). The `Program` moduledoc further describes it as "afterschool program, camp, or class trip" — but `afterschool` and `class trip` are not categories at all.
**Resolution (direction, not yet built):** Afterschool programs, **Camps**, and **Class Trips** are considered *structurally different* offerings (e.g. multi-day vs recurring weekly, different booking/pricing rules) and are expected to become **distinct entities** down the line — not values of one enum. Until then, treat "Program" as the umbrella but do not encode kind into **Category**. When the split happens, **Category** stays subject-only.

**Sessions are hand-created, not generated from the Program schedule.**
A Program stores a recurring schedule (meeting days + meeting start/end times + a date range), but **Sessions** are today created manually one at a time, so those Program fields are merely *advertised* schedule and enforce nothing — the real schedule is the set of Sessions.
**Resolution (direction, not yet built):** This is a design shortcoming. Since the Program already holds the data needed to derive its Sessions, Sessions *should* be generated from the Program's recurring schedule rather than entered by hand. Until then the duplication is accidental, not intentional.

**"Instructor" does double duty.**
The word names both a *responsibility* (the lead Staff Member running a Program/Session) and a *display snapshot* (the read-only copy of that person's name/headshot held in the Program Catalog). The snapshot is captured at Program creation, so it goes **stale** if the underlying Staff Member is renamed — the same denormalisation hazard as the `program_name` projection.
**Resolution:** Keep "Instructor" for the lead responsibility. Treat the catalog copy as a derived display projection that must be refreshed from Provider data (via events), not hand-maintained.

**Session-level staffing is not modelled.**
A Staff Member (and a lead **Instructor**) can conceptually be assigned to a single **Session**, not just a whole **Program** — a class may need different people on different days. Today only `Program Staff Assignment` exists (Program-level); a Session has a child **Roster** but no staff assignment.
**Resolution (direction, not yet built):** Session-level staff assignment is a recognised gap, not a decision to keep staffing Program-only.

**"Participant" collides with "Participation".**
Messaging's **Participant** is a conversation member (a **User**). The Participation context tracks children at **Sessions** through **Participation Record** and deliberately never uses the noun "Participant" for them.
**Resolution:** "Participant" means *conversation member* only. A child attending a Session is a **Roster** entry / **Participation Record** — never a "participant".

**"Booking" is a verb, not an entity.**
"Book"/"Booking" lives almost entirely in the web/UI layer (front-of-house), while the domain records an **Enrollment**. They are the same concept under two names, not two concepts.
**Resolution:** "Enrollment" is the only domain noun for the record. "Book"/"Booking" may appear in UI copy and route names but must never become a domain noun or a second entity (e.g. a multi-enrollment cart) unless that distinct concept is deliberately introduced and defined here.

**"Behavioural" is no longer overloaded (resolved).**
The per-child, parent-approved feedback entity was named `BehavioralNote` in code, but it is usually positive and collided with the `behavioral_issue` category on **Incident Report**.
**Resolution:** #924 renamed the entity, its table, its events, and its UI copy to **Session Note**. "Behavioural" is now reserved exclusively for the safeguarding-level `behavioral_issue` **Incident Report** category. Do not reintroduce "behavioural" for routine feedback.

**Subscription tiers and the Entitlements service are removed (resolved).**
Both provider tiers (ADR-0004) and parent tiers (ADR-0007) are gone: every Provider and Parent has full access, the Shared **Entitlements** service and tier vocabulary are deleted, and the `:active` tier vs `active` lifecycle-flag collision no longer exists. A **success-based fee** on platform income is the planned monetisation model (not yet built). Do not reintroduce `subscription_tier` or an `Entitlements` service.

**"Participation" is overloaded across context, record, and consent.**
The word names the Participation *context*, the **Participation Record** (roster row), and a `participation` **Consent** type.
**Resolution:** Bare "participation" means attendance/roster only. The Consent type is being renamed `participation → activity_participation` so the word never also means consent.

**The Support Inbox lives inside the Messaging context but shares no data with it.**
**Inbound Email** / **Email Reply** (external email via Resend, Admin-operated) are co-located in Messaging yet share no rows or associations with in-app **Conversation**/**Message**. "Message" is in-app only; "Email" is the inbox only.
**Resolution:** Keep them as distinct subsystems with no shared schema. The inbox stays co-located in Messaging for now; extracting it into its own **Support** bounded context is deferred until the inbox grows its own domain (assignment/SLA/richer status, or a second external channel). See ADR-0003.
