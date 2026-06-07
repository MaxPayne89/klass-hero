# Provider subscription tiers are removed; a success-based fee will replace them

Provider subscription tiers (`starter`, `professional`, `business_plus`) are removed from the platform. Every Provider receives full access: unlimited Programs, all media types, unlimited team seats, and the right to initiate Messaging (Broadcasts and Direct Conversations). The tier-linked commission rates (18% / 12% / 8%) are deleted with them — no flat placeholder rate remains in code.

The replacement model is a **success-based fee** calculated from a Provider's income earned through the platform ("we earn when you earn"). That fee system is deliberately *not* designed or stubbed here; it will be introduced as its own module when built. Keeping a dead commission constant or an empty fee port would have meant config pretending to be live behaviour.

Tiers could be removed this bluntly because they were never monetised: the €19/€49 prices were displayed but no payment integration was ever wired, so no Provider pays today, and removal is a strict silent upgrade for every existing account. Both storage columns (`providers.subscription_tier` and the legacy `users.provider_subscription_tier`) are dropped in the same change — the old tier value carries no information the future fee model needs.

**Parent tiers (`explorer`, `active`) are explicitly out of scope.** They remain live and continue to gate parent capabilities through the Shared Entitlements service. The broader direction (CONTEXT.md flagged ambiguity: all tiers and Entitlements eventually retire) still stands; this ADR executes only the Provider half.

## Consequences

- The Provider half of `Shared.Entitlements` (program caps, media gating, team seats, provider messaging gate, commission rates, `provider_tier_bypass` flag) is deleted, not bypassed. The parent half stays.
- Staff Members inherit messaging rights from their Provider; with the gate gone, **all staff of all Providers can broadcast** — a behaviour change beyond Providers themselves.
- The tier-change feature disappears end-to-end: subscription management page, `ChangeSubscriptionTier` command, `subscription_tier_changed` domain/integration events and their promotion handler. No consumer of those events ever existed, so nothing is migrated.
- Provider registration no longer asks for a plan; `/for-providers` marketing sells "free to join, all features included, success-based fee coming" instead of three pricing cards.
- The column drop ships in the same PR as the code removal (single deploy, low traffic); a brief window where an old release selects a dropped column is accepted.

## When to revisit

- When the success-based fee is built: it defines its own fee schedule, storage, and statements from scratch — it must not resurrect tier vocabulary or the Entitlements provider map.
- If provider-side capability gating is ever needed again (e.g. fee-delinquent Providers losing features), model it on the fee system's own state, not on a reintroduced tier.
