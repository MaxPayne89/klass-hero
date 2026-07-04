---
name: read-and-assess-issue
description: This skill should be used when the user wants to assess or scope a GitHub issue before committing to work — triggers on "assess issue #N", "scope issue #N", "read issue #N", "look at issue #N", "should we do #N", or "how big is issue #N". Weighs the fix's blast radius on the codebase, not just its size, and stops to discuss when the proper fix diverges from the quick one.
---

# Read and assess a GitHub issue

Assess an issue on two axes that most sizing skips: how much **effort** the fix
takes, and how large its **blast radius** on the codebase is. The blast radius is
the point — a naive assessment sizes the visible change and stays blind to
whether that change entrenches debt, papers over a deeper flaw, or violates the
architecture. Surface that before scoping, not after the code lands.

Two guardrails pull against each other; hold both:

- **Stay focused on fixing the issue.** Most issues are exactly what they look
  like. Do not turn every ticket into an architecture rant — that is its own
  failure.
- **But when the blast radius exceeds the issue, stop and discuss.** The moment
  the *right* fix diverges from the *quick* fix, that divergence is the user's
  call, not a detail to bury in a scope list.

Issues live in the `MaxPayne89/klass-hero` GitHub repo.

## 1. Resolve the issue

Take the issue number from the user's request. If none was given, ask for one
before doing anything else.

## 2. Fetch it

```bash
gh issue view <number> --json title,body,labels,state,comments,assignees
```

If the issue does not exist or the command fails, report the error and stop.
Read the comments too — prior discussion often already names the deeper problem.

## 3. Do the legwork

This is where a shallow read produces a shallow assessment, so the criterion is
exhaustive, not "as needed". The work is done only when **both** hold:

- **Every file the fix would touch has been opened.** Trace the actual code
  paths from the issue's symptom to the code that produces it — the LiveView, the
  context function, the schema, the projection. Do not assess from the issue text
  alone.
- **The intended fix has been checked against the architecture.** Read the
  affected bounded context and `.claude/rules/domain-architecture.md`. Ask
  whether the obvious fix fits the conventions there or fights them.

Then name the **root cause**: is this issue the actual problem, or a *symptom* of
something deeper (a missing abstraction, a boundary already being violated, a
projection that never subscribed to the right event)? The symptom-vs-root-cause
call drives everything downstream.

## 4. Assess on two axes

Keep these separate — a one-line fix can have a huge blast radius, and a large
mechanical change can have almost none. Fusing them into one rating is how the
blast radius gets lost.

**Effort** (how much work) — rate low / medium / high on:
- number of bounded contexts touched
- whether a database migration is needed
- new code vs modification of existing code
- test surface (what needs writing or updating)

**Blast radius** (how far the consequences reach) — rate low / medium / high on:
- symptom vs root cause (a symptom fix that leaves the cause is high blast radius
  even when it is one line)
- whether the quick fix would violate a documented architecture rule —
  schema-as-struct integrity, context boundaries, no reintroduced ports/DI,
  correct CQRS/projection placement (see `.claude/rules/domain-architecture.md`)
- whether it entrenches an existing bad pattern or adds debt that later work pays
  interest on
- whether the proper fix forces a contract or schema change wider than the issue
  itself

## 5. Gate on blast radius

Decide whether the blast radius has tripped the gate. The trip conditions and the
discussion format live in [`references/blast-radius.md`](references/blast-radius.md);
consult it now to make the call.

- **Not tripped** — the quick fix *is* the right fix. Take the minimal-fix path:
  emit the assessment (section 6) and stop. This is the common case; keep it fast.

- **Tripped** — the proper fix diverges from the quick one. Do **not** emit a tidy
  scope and move on. Load `references/blast-radius.md` and follow it: present
  quick-fix vs proper-fix with tradeoffs and a recommendation, drive the decision
  through `AskUserQuestion`, and scope only the path the user chooses. If the
  deeper problem deserves its own ticket, offer to file it with the `create-issue`
  skill.

## 6. Output the assessment

```
## Issue #<number>: <title>

### Validity
- **Valid:** yes/no
- **Reason:** <is it well-defined, actionable, and about real code here?>

### Root cause
- **This issue is:** the real problem | a symptom of <deeper cause>

### Effort
- **Rating:** low | medium | high
- **Factors:** <what drives the effort>

### Blast radius
- **Rating:** low | medium | high
- **Factors:** <symptom/root-cause, architecture-rule fit, debt, contract reach>

### Scope of changes (if valid)
- **Bounded contexts:** <which are affected>
- **Files/modules:** <key files that would change>
- **Migration needed:** yes/no
- **Test impact:** <what tests need writing/updating>
- **Dependencies:** <new deps or cross-context coordination>

### Recommended approach
- <the fix you recommend, and — if the gate tripped — which of quick/proper the
  user chose and why>
```
