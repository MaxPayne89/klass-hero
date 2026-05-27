---
name: design-flow
description: >-
  Design a new user flow before building it, or audit an existing flow for friction,
  using the product-flow-designer agent. Use when: planning a new multi-step feature
  (onboarding, signup, booking, invite, wishlist) before implementation, or auditing a
  conversion journey for drop-off, dead-ends, or mobile friction. Invoke with:
  /design-flow <flow> [design|evaluate]
---

# Design Flow

Run a focused user-flow session with the `product-flow-designer` agent, then hand the result
to the right next step. One agent, two modes — **DESIGN** (a journey that doesn't exist yet) and
**EVALUATE** (an existing journey).

**Type:** Rigid workflow, single-agent. Follow steps exactly. The whole point is to drive the
specialized agent and wire its output downstream — do NOT hand-roll a flow yourself in its place
(see Rules).

This is a *journey-level UX* tool. It is not a per-PR review (that's `review-design`) and not a
functional QA pass (that's `test-drive`, which asks "does it work" — this asks "is it low-friction").

---

## Step 1: Resolve Flow and Mode

Parse `<flow>` and the optional mode from the invocation.

- **Mode given** (`design` | `evaluate`): use it.
- **Mode omitted:** infer — grep `lib/klass_hero_web/router.ex` for the flow. Has a route → default
  **evaluate** (it exists). No route → default **design** (it's new). If the request is "redesign
  the existing X" or otherwise ambiguous, confirm with the user before proceeding.

High-value journeys worth auditing (suggest these when the user is vague about *which* flow):
booking/enrollment, registration→activation, provider onboarding, staff invite/claim.

Then branch to Step 2A (design) or Step 2B (evaluate).

## Step 2A: DESIGN (upstream — before code exists)

No server needed; this mode is generative.

Spawn **one** `product-flow-designer` subagent in DESIGN mode:

```
Design the "<flow>" user flow. It does not exist yet.

Mode: DESIGN. Anchor to the nearest existing klass-hero flow + pattern — REQUIRED: name a real
route/module, don't hand-wave it. Use the real personas. Label every step (proposed). Produce the
journey flow map, anticipated friction, edge cases, and success metrics — NOT an implementation/DDD design.
```

Keep the output at **journey granularity** (screens, steps, decisions, friction) — bounded contexts,
ports, and Ecto belong to the plan, not here.

**Handoff (do not skip):**
- If the intent is still fuzzy, recommend `superpowers:brainstorming` first.
- Then hand the flow map into `superpowers:writing-plans` as the starting point for the
  implementation plan. Do **not** write code from this skill.

## Step 2B: EVALUATE (audit an existing journey)

**Server preflight (required).** The agent must *walk* the journey — a code read is not an audit.
Probe `http://localhost:4000` and one real route (e.g. the flow's entry route): the server must be
**healthy** (2xx/3xx), not merely listening. A stale process returning `5xx` counts as down.

- **Healthy:** proceed.
- **Down or 5xx:** ask the user to (re)start it (`mix phx.server`). If they decline, **STOP** —
  do not let the agent audit from code alone (it would miss the rendered/mobile dead-ends, which is
  exactly what RED testing showed a code-only pass misses).

**Resolve dynamic route params first.** If the entry route has a dynamic segment (e.g.
`/programs/:id/booking`), resolve `:id` to a **real seeded record** before walking — navigate in
from the listing page, or query a valid id (Tidewave / a quick SQL select). Walking a bogus id
audits the redirect, not the actual screen. Pass the resolved URL to the agent.

Spawn **one** `product-flow-designer` subagent in EVALUATE mode:

```
Evaluate the "<flow>" flow for friction.

Mode: EVALUATE. Entry route: <resolved URL, real ids>. Role: <parent|provider|admin> (log in with the seed user).
Server: http://localhost:4000 (confirmed healthy). Read router + LiveViews to map it, then WALK it
at 375 and 1280, screenshotting each step and every branch (error/empty/validation/role wall).
Produce the flow map with counts (steps/fields/decisions/taps), quantified friction, and severity.
```

**Handoff (do not skip):** after presenting the report, **offer** to file each **Blocker / Major**
finding as a GitHub issue via `/create-issue "<finding>"` — one invocation per finding. Let
`create-issue` validate against code, dedup, classify, and pick labels (it selects `design` for UX
issues; the repo has no `frontend` label). **Never auto-file without the user's confirmation.**

---

## Rules

- **Single agent, no fan-out.** Spawn exactly one `product-flow-designer`. This is not
  `review-design` — do not parallel-spawn or consolidate multiple agents.
- **Always spawn the agent.** Do NOT substitute your own hand-sketched flow or audit. The failure
  this skill prevents is improvising a manual pass and skipping the specialized agent (and, for
  evaluate, skipping the live walk).
- **Mode discipline.** DESIGN = generative, every step `(proposed)`, journey-level (no DDD/Ecto).
  EVALUATE = grounded in router+LiveViews and *walked* in the browser. Never blur them.
- **Server-healthy gate for evaluate.** Healthy response required; 5xx = down; STOP rather than
  audit from code only.
- **Honour the handoffs.** DESIGN → `writing-plans` (after optional `brainstorming`). EVALUATE →
  offer per-finding `/create-issue` for Blocker/Major. The skill's job is routing + handoff, not
  redoing the agent's work or writing code.
- **Not functional QA.** `test-drive` covers "does it work"; this covers "is it low-friction." Don't
  duplicate it.
```
