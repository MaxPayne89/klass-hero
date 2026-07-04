# Blast radius: trip conditions and the discussion

Loaded from `SKILL.md` step 5. This file decides *when* an issue's blast radius is
large enough to stop and discuss, and *how* to run that discussion.

## Trip conditions

The gate trips when the **proper** fix diverges from the **quick** fix by enough
that the choice belongs to the user. Evaluate each condition against the legwork
from step 3. Any single one tripping is enough.

1. **Symptom fix leaves the cause.** The quick fix makes the reported behaviour
   correct but the root cause named in step 3 still stands — the same class of bug
   can recur from the untouched cause.

2. **The quick fix breaks a documented rule.** The obvious fix would violate a
   convention in `.claude/rules/domain-architecture.md` — cross-context access
   outside a facade/ACL, reintroduced ports/DI, business logic outside its
   schema-as-struct entity, a read path that bypasses its projection, or a
   `Multi.run` side-effect. (When unsure a rule is broken, treat it as tripped —
   that is what the discussion is for.)

3. **The fix reaches into a shared abstraction.** The change edits `shared/`, a
   projection base macro, an event/envelope contract, or another module many
   callers depend on — so the blast radius is every consumer, not the one issue.

4. **The proper fix forces a wider contract or schema change.** Doing it right
   requires a migration, an event-payload change, or a public-API signature change
   beyond what the issue literally asks for.

5. **The root cause lives in another bounded context.** The symptom surfaces in
   one context but the fix that removes it belongs in a different context's code —
   so scoping this issue alone would push the change to the wrong place.

If none trip, the quick fix is the right fix — do not manufacture a debate.

## When tripped: run the discussion

Do not emit a scope yet. Present both fixes side by side, then let the user
choose. For **each** of the two options give:

- **Changes** — what code actually moves.
- **Cost now** — effort and risk to ship this path.
- **Cost later** — the debt or entrenchment the codebase carries if this path
  wins (the whole reason the gate exists).

Then give a **one-line recommendation** — which path you would take and why —
and drive the decision through `AskUserQuestion` (options: quick fix, proper fix;
recommended one first). Scope only the chosen path back in `SKILL.md` step 6.

Suggested shape:

```
### Blast radius exceeds the issue

**Quick fix** — <changes>
- Cost now: <effort/risk>
- Cost later: <debt/entrenchment>

**Proper fix** — <changes>
- Cost now: <effort/risk>
- Cost later: <what it avoids>

**Recommendation:** <one line>
```

If the deeper problem is worth tracking regardless of which path wins, offer to
file it as its own ticket with the `create-issue` skill.

## Optional deep handoff

When the blast radius is high and the user wants more rigor than this skill's own
judgment, hand off rather than hand-roll the analysis:

- `improve-codebase-architecture` — to find the deepening the proper fix implies.
- `/review-architecture` (architecture-reviewer, boundary-checker) — to confirm
  which rules the quick fix would break.

Lightweight by default: offer these, do not auto-spawn them. Spawning heavy
review on a borderline issue is the tornado the gate exists to prevent.
