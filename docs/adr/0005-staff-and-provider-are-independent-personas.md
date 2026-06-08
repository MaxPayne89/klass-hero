# Staff Member and Provider are independent personas of one User

A **User** (the person) may hold any combination of personas — **Parent**, one or more **Staff Member** records, and/or a **Provider** — each a distinct record in its own context, correlated to the User by id. Being one persona never implies another. In particular: **being hired as staff does not make you a Provider, and being a Provider does not make you Staff.** Both directions are deliberate, person-initiated acts.

Previously the two were conflated. Accepting a staff invitation ran a registration that hard-coded `intended_roles = [:staff_provider, :provider]` and auto-created a draft `ProviderProfile` (`originated_from = "staff_invite"`). Every hired staff member silently became a "provider"; the very role atom `:staff_provider` encoded the assumption. This blocked the gating/vetting milestones (Business Vetting, milestone 23), which must gate *the Provider entity* — meaningless if everyone is already a provider.

## Decision

- **Provider-hood is always deliberate.** It is created only by self-registration as a provider, or by an existing Staff Member explicitly *upgrading* ("do my own thing") via a CTA. Never automatic from being hired; never created by an Admin on someone's behalf (the vetting red tape must be undertaken by the person).
- **The staff-invite accept flow links, it does not force-register.** It branches like the enrollment invite (`:new_user | :existing_user`): a new email creates an account (role `:staff` only); an email that already belongs to a User links the pending `StaffMember.user_id` to that User and appends `:staff`. A logged-in user whose session email matches the invite links in one click. This is what makes **multi-employer staff** possible — one person, many `StaffMember` rows.
- **`:staff_provider` is renamed `:staff`.** Roles are `[:parent, :provider, :staff]`. Founder-who-teaches = `[:provider, :staff]`.
- **Authorization authority is persona existence** (`Scope.provider?/1`, `Scope.staff?/1`), already true for the on_mount guards. `intended_roles` is retained as signup-intent, default-landing hint, and eventual-consistency bridge (personas are created asynchronously by event handlers); it is kept in step by appending the matching atom whenever a persona is gained. It is not the authorization source of truth.
- **A Provider who teaches self-staffs deliberately.** A `ProviderProfile` is not assignable to a Program — only a `StaffMember` is (Instructor = the lead Staff Member). A Provider who wants to teach adds themselves as a Staff Member of their own business, created already-linked to their User (no invitation token, status `:accepted`). A pure-business Provider never becomes a Staff Member, keeping `staff?` honest.

## Consequences

- `StaffInvitationStatusHandler` no longer creates a `ProviderProfile`; `staff_registration_changeset` no longer forces `:provider`. The `originated_from = "staff_invite"` origin becomes vestigial (all Providers are now deliberate/"direct").
- Landing for a person who is both is **provider-takes-precedence** (`signed_in_path`); a dashboard switcher is deferred.
- **Migration (blanket):** rename `:staff_provider → :staff` in all `intended_roles`; delete every `ProviderProfile` with `originated_from = "staff_invite"` and strip `:provider` from those Users. Safe as a blanket op because no staff member has yet acted as a side-hustle provider (zero such profiles carry Programs at migration time). Had any existed, the policy would have been activity-gated.
- The `provider-verification.allium` spec's staff/grandfathering notes (which assume staff hold a "progression-path" provider profile and get a dormant case at invite-claim) are now **wrong** and need a follow-up tend: a verification case attaches to a `ProviderProfile` created by the deliberate act, not at invite-claim.
- This is the entity/identity separation only. Vetting/gating itself (milestones 16, 23) is downstream and out of scope here; it keys off "does a ProviderProfile exist?" instead of "was someone invited?".

## When to revisit

- If person-level data (bio, headshot, qualifications) needs to be shared across a multi-employer person's many `StaffMember` rows rather than duplicated, factor out a shared Person/Practitioner entity that both `StaffMember` (employment) and `ProviderProfile` reference. Deferred; the `User` plays the person role for now.
- If the both-persona population grows, replace provider-precedence landing with a remembered/last-used dashboard switcher.
