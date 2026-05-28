# Klass Hero

The domain glossary for Klass Hero — a platform for afterschool activities, camps, and class trips that connects parents, providers, and instructors. This file defines the language we use; it is not a spec.

## The Offering

**Program**:
A bookable offering a Provider lists for children to attend. Today a single `Program` entity serves all offering kinds, distinguished by a subject **Category**. It carries a recurring schedule (the days/times it meets) and a **Registration Period**.
_Avoid_: Activity, Class, Course, Offering, Listing

**Category**:
The *subject* of a Program — what it is about. Current values: `sports`, `arts`, `music`, `education`, `life-skills`. This is one axis only and must not carry format/kind information.
_Avoid_: Type, Kind, Tag

**Registration Period**:
The window during which parents may enrol in a Program. When unbounded, registration is "always open".
_Avoid_: Enrolment window, Signup period, Booking window

## Scheduling

**Session**:
A single dated occurrence of a Program (a date plus start/end time) that children attend and staff run. The Program attachment is implicit — we just say "Session", never "Program Session". Has its own lifecycle: `scheduled → in_progress → completed`, or `cancelled`.
_Avoid_: Class, Meeting, Occurrence, Program Session; and never reuse "Session" for the authentication session

## Enrollment & Attendance

**Enrollment**:
A child's signup to a **Program** — the program-level commitment, made once. Feeds the **Roster** of every Session in that Program. Parents "book" a Program; the record that results is an Enrollment.
_Avoid_: Registration, Signup; and "Booking" as a domain *noun* ("Book" is fine as a front-of-house verb only — see flagged ambiguities)

**Roster**:
The set of children expected at a given **Session**, seeded from the Program's active **Enrollments**. A roster belongs to one Session.
_Avoid_: Attendance list, Class list, Sign-in sheet

**Participation Record**:
One child's row on one Session's Roster, tracking presence through `registered → checked_in → checked_out`, or `absent`. `registered` here means "on the roster, not yet arrived" — it is not the **Enrollment**.
_Avoid_: Attendance record, Booking

**Attendance**:
The act and result of checking a child in and out of a **Session** (the state changes recorded on a **Participation Record**).
_Avoid_: Presence, Sign-in

## Providers & Staff

**Provider**:
The business or organisation that lists **Programs** and employs **Staff Members**. Parents see the Provider as the entity behind a Program. Modelled as the `ProviderProfile` struct (DB table `providers`); "Provider" and "ProviderProfile" are the same thing — the profile *is* the provider, and `provider_id`/`provider_profile_id` point at it interchangeably.
_Avoid_: Vendor, Merchant, Business, Partner, Organiser

**Staff Member**:
A person who works for a **Provider**. May be invited to claim a **User** account, may be assigned to one or more **Programs**, and carries a **Role**, qualifications and pay rate.
_Avoid_: Employee, Team member, Worker

**Instructor**:
The lead **Staff Member** responsible for running a Program — the "boss" for that Program (or for a specific **Session**). Exactly one Instructor leads, even though several Staff Members may be assigned alongside them. In the Program Catalog this person also appears as a read-only display copy.
_Avoid_: Teacher, Coach, Trainer (those are **Roles**, not the lead responsibility)

**Role**:
A **Staff Member**'s specific job title — freeform text such as "Coach" or "Teacher". Distinct from **Instructor**, which is the lead responsibility for a Program/Session, not a title.
_Avoid_: Position, Title, Type

**Program Staff Assignment**:
The link recording that a **Staff Member** works on a **Program**. Many Staff Members may be assigned to one Program because a class can need several people.
_Avoid_: Membership, Posting

## Families & Accounts

**User**:
An authentication identity in the Accounts context — email, password, role. A person logs in as a User; their domain persona (**Parent**, **Staff Member**) lives in another context and links back by a correlation id, not a foreign key.
_Avoid_: Account, Login, Member

**Admin**:
A platform operator (not a **Parent** or **Provider**) who reviews **Verification Documents** and **Incident Reports** and approves pending **Enrollments**. The reviewer behind `reviewed_by_id`.
_Avoid_: Moderator, Superuser, Staff (Staff belongs to a Provider)

**Parent**:
The account-holding persona who manages **Children**, books **Programs**, and pays. A Parent is a **Guardian** who holds a **User** account.
_Avoid_: Customer, Buyer, Family (Family is the context, not the person)

**Guardian**:
Any adult with a custodial relationship to a **Child**. A Child has one *or more* Guardians (e.g. two parents plus a grandparent); not every Guardian necessarily holds an account. Multiple guardians per child is intended, not incidental.
_Avoid_: Parent (reserve that for the account-holding role), Caregiver, Custodian

**Child**:
A young person who attends **Programs**, belonging to one or more **Guardians**. The person a **Parent** enrols and a **Roster** tracks.
_Avoid_: Kid, Student, Participant, Attendee

**Subscription Tier** _(being removed — see flagged ambiguities)_:
The plan a **Parent** (`explorer`, `active`) or **Provider** (`starter`, `professional`, `business_plus`) currently holds, gating capabilities (**Entitlements**) such as booking caps or the platform **Commission** rate. Slated for removal — do not build new behaviour on it.
_Avoid_: Plan, Level, Membership

## Messaging

**Conversation**:
A messaging thread between **Users** (typically a **Parent** and a **Provider**).
_Avoid_: Thread, Chat, Channel

**Message**:
A single entry within a **Conversation**.

**Participant** (Messaging):
A **User**'s membership in a **Conversation** — tracks join/leave and read receipts. This is the *only* meaning of "Participant" in the system; it is **not** a child attending a Session.
_Avoid_: using "Participant" for a child on a **Roster** (that's a **Participation Record**)

## Safeguarding & Feedback

**Incident Report**:
A formal safeguarding/operational record of an event during a **Program** or a **Session** — injury, safety concern, property damage, policy violation, or a serious behavioural incident. Filed by a Provider's staff, severity-rated (`low`–`critical`), routed to admins, and never parent-approved.
_Avoid_: Note, Complaint, unqualified "Report"

**Session Note**:
Routine per-child feedback from the **Instructor** about one **Child** at one **Session** (often positive, e.g. "very engaged today"). The **Parent** must approve it before it is shared; a rejected note can be revised. Attached to the child's **Participation Record**.
_Avoid_: Behavioral Note (current code name, being retired), Feedback, Review, Comment

## Trust & Compliance

**Consent**:
A **Guardian**'s recorded permission for a specific **Child** and a specific purpose — `photo_marketing`, `photo_social_media`, `medical`, `activity_participation` (currently `participation` in code — rename pending), or `provider_data_sharing`. Append-only for audit: re-granting or withdrawing adds a new record; the live state is the latest non-withdrawn one.
_Avoid_: Permission, Agreement, Opt-in

**Verification Document**:
A document a **Provider** uploads for **Admin** review to establish trust — `business_registration`, `insurance_certificate`, `id_document`, `tax_certificate`. Lifecycle `pending → approved / rejected`.
_Avoid_: Credential, Proof; "Certificate"/"Registration" name *document types*, not the concept

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

**"Behavioural" is overloaded; the feedback note should be a Session Note.**
The per-child, parent-approved feedback entity is named `BehavioralNote` in code, but it is usually positive and collides with the `behavioral_issue` category on **Incident Report**.
**Resolution:** Canonical term is **Session Note** for routine per-child feedback; reserve "behavioural" for the safeguarding-level `behavioral_issue` **Incident Report** category. A code rename `BehavioralNote → SessionNote` is pending.

**Subscription tiers and the Entitlements service are being removed.**
Today **Subscription Tier** gates Parent and Provider capabilities through the Shared **Entitlements** service, and the paid parent tier `:active` collides with the pervasive `active` lifecycle flag (`StaffMember.active`, `ProgramStaffAssignment.active?`, etc.).
**Resolution (direction, not yet built):** Tiers are being dropped entirely. Once removed, the Entitlements service loses all functionality, the tier vocabulary (`explorer`/`active`/`starter`/`professional`/`business_plus`) retires, and the `:active` collision disappears on its own. Do not build new behaviour on tiers or Entitlements.

**"Participation" is overloaded across context, record, and consent.**
The word names the Participation *context*, the **Participation Record** (roster row), and a `participation` **Consent** type.
**Resolution:** Bare "participation" means attendance/roster only. The Consent type is being renamed `participation → activity_participation` so the word never also means consent.
