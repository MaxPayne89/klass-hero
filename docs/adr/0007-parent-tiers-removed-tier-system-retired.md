# Parent subscription tiers are removed; the tier system is fully retired

Parent subscription tiers (`explorer`, `active`) are removed from the platform. Every Parent now has full access: unlimited monthly bookings and the right to initiate Messaging. The Shared `Entitlements` service and `SubscriptionTiers` vocabulary — whose only remaining consumers were the parent half — are deleted, along with the `:parent_tier_bypass` feature flag and the `parents.subscription_tier` column.

This completes the tier retirement begun for providers in ADR-0004. With both halves gone, the `Subscription Tier` concept, the `Entitlements` service, and the tier vocabulary (`explorer`/`active`/`starter`/`professional`/`business_plus`) are entirely retired. As a side effect, the name collision between the paid parent tier `:active` and the pervasive `active` lifecycle flag (`StaffMember.active`, `ProgramStaffAssignment.active?`) disappears — there is no longer an `:active` tier.

Parent tiers could be removed this bluntly for the same reason provider tiers could: they were never monetised. Prices were displayed but no payment integration was ever wired, so no Parent pays today and removal is a strict silent upgrade for every existing account.

## What changed

- **Enrollment**: the monthly booking cap is gone. `create_enrollment` no longer consults `ensure_booking_capacity`; the booking-usage meter (`get_booking_usage_info`, the `pa_booking_usage` component, and the booking-limit UI in the dashboard and booking flow) is deleted. `count_monthly_bookings/2` survives as a tier-agnostic query.
- **Messaging**: the messaging-initiation predicate moved from `Shared.Entitlements.can_initiate_messaging?/1` to `KlassHero.Messaging.can_initiate_messaging?/1`. It no longer consults a tier: any Parent or Provider (including a Staff Member acting for a loaded Provider) may initiate; only a pure staff-only scope (no provider, no parent) and an unrecognised scope shape are denied.
- **Family**: `ParentProfile.subscription_tier` (an `Ecto.Enum`) is dropped from the schema and the database in the same PR as the code removal (single deploy; a brief window where an old release selects a dropped column is accepted, as in ADR-0004).
- **Shared**: `Shared.Entitlements` and `Shared.SubscriptionTiers` are deleted, along with the dead tier converters in `mapper_helpers.ex` and `Scope.parent_tier/1`. The `:parent_tier_bypass` FunWithFlags flag is removed (no config artifact).
- **Admin**: the Backpex "Subscription" column on the accounts view is removed; the "Roles" column (Parent/Provider/Admin/User badges) is unaffected.

## Consequences

- There is no capability gating on parents anymore. Any future parent-side gating must be modelled on its own state (e.g. a payment/fee system), not on a reintroduced tier or a resurrected `Entitlements` service.
- The `Entitlements` name and the tier vocabulary must not return. If a success-based fee is built (per ADR-0004), it defines its own state and vocabulary from scratch.

## When to revisit

- If parent-facing plans are ever monetised, model them as a distinct billing concept with its own storage and vocabulary — do not reintroduce `subscription_tier` or `Entitlements`.
