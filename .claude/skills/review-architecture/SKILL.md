---
name: review-architecture
description: >-
  Review code changes for conventional-Phoenix convention compliance by
  spawning the architecture-reviewer (8 structural checks), boundary-checker
  (5 semantic violation checks), and regression-analyzer (8 behaviour-
  preservation checks) agents in parallel. Consolidates findings into a unified
  report. Use when: reviewing a PR, checking architecture before merge,
  validating structural changes, or after modifying bounded context code.
  Invoke with: /review-architecture
---

# Review Architecture

Run a comprehensive conventional-Phoenix convention review (post-flatten:
schema-as-struct, no ports/DI/Boundary, cross-context via facade) by dispatching
three specialized agents in parallel, then consolidating their reports.

**Type:** Rigid workflow. Follow steps exactly.

---

## Step 1: Determine Changed Files

Detect the review scope — what files have changed relative to the base branch.

```bash
# If on a PR branch, diff against the base
BASE=$(git merge-base HEAD main 2>/dev/null || echo "main")
git diff --name-only "$BASE"...HEAD -- '*.ex' '*.exs'
```

If there are unstaged changes (no commits yet), also include:

```bash
git diff --name-only -- '*.ex' '*.exs'
```

Filter to only Elixir files under `lib/klass_hero/` and `config/` — ignore test files,
migrations, and assets for the architecture review.

Store the file list for passing to both agents.

If no Elixir files changed, STOP:

```
No Elixir source files changed. Nothing to review.
```

## Step 2: Identify Affected Contexts

From the changed file paths, extract which bounded contexts are touched:

- `lib/klass_hero/enrollment/...` -> Enrollment
- `lib/klass_hero/family/...` -> Family
- `config/config.exs` -> Cross-cutting (event handlers, scopes)

Display: `Affected contexts: Enrollment, Family, Shared`

This helps the user understand the review scope.

## Step 3: Spawn All Three Agents in Parallel

Launch all three agents **in the same message** so they run concurrently.

### Agent 1: Architecture Reviewer

Use the `architecture-reviewer` subagent. In the prompt, provide:

- The list of changed files
- The affected contexts
- Instruction to focus the 8 checks on changed files and their surrounding context

Example prompt:

```
Review these changed files for conventional-Phoenix convention compliance
(schema-as-struct; no reintroduced ports/DI/Boundary; cross-context via facade;
correct placement of projections/events/workers/ACL).
Focus your 8 checks on these files and the contexts they belong to.

Changed files:
<file list>

Affected contexts: <context list>

Run all 8 checks but scope them to the changed files and their immediate
context directories. Report findings in your standard output format.
```

### Agent 2: Boundary Checker

Use the `boundary-checker` subagent. In the prompt, provide:

- The list of changed files
- Explicit scope: `changed-files`

Example prompt:

```
Check these changed files for semantic boundary violations.

Scope: changed-files

Changed files:
<file list>

Run all 5 checks scoped to these files and their immediate references.
Report findings in your standard output format.
```

### Agent 3: Regression Analyzer

Use the `regression-analyzer` subagent. In the prompt, provide:

- The diff base (default `main` for PR reviews, `HEAD` for unstaged)
- Explicit scope mode: `pr-diff` (default) or `unstaged`
- The list of changed files (the agent can re-derive it but passing it helps)

Example prompt:

```
Analyse the diff for behaviour-preservation regressions.

Scope: pr-diff (base: main)

Changed files:
<file list>

Run all 8 checks against the diff. For producer/consumer pair checks (#4),
grep the codebase for matching subscribers — same-context inspection is
insufficient. Report findings in your standard output format.
```

## Step 4: Consolidate Reports

Once both agents complete, merge their findings into a single unified report.

### Deduplication

Agents may flag the same issue from different angles:
- Cross-context access → caught by architecture-reviewer Check 4 (facade) AND boundary-checker Check 1/2
- Read-model / event-struct purity → caught by architecture-reviewer Check 7/8 AND boundary-checker Check 4
- A reintroduced port/DI → architecture-reviewer Check 3 AND (if it changes a config-read side effect) regression-analyzer

Deduplicate by matching on the same file + line + violation type. Keep the more detailed description. For overlaps between regression-analyzer and the other two, prefer the regression-analyzer's framing — it speaks specifically to behaviour preservation, which is the action-shaping concern.

### Unified Report Format

```markdown
# Architecture Review Report

**Branch:** [branch name]
**Affected contexts:** [list]
**Files reviewed:** [count]

## Summary

| Source | Checks | Passed | Violations | Warnings |
|--------|--------|--------|------------|----------|
| Structure (architecture-reviewer) | 8 | N | N | N |
| Boundaries (boundary-checker) | 5 | N | N | N |
| Behaviour (regression-analyzer) | 8 | N | N | N |
| **Total** | **21** | **N** | **N** | **N** |

## Violations

### [SEVERITY: error] CHECK_NAME — description
- **File:** path/to/file.ex:line
- **Issue:** What is wrong
- **Fix:** How to fix it

### [SEVERITY: warning] ...

## Passed Checks
- [list of all checks that passed cleanly]
```

Order violations by severity (errors first, then warnings), then by file path.

## Step 5: Present and Advise

After presenting the report:

- If **zero violations**: confirm the changes are architecturally sound
- If **only warnings**: note them but confirm the changes are acceptable
- If **errors found**: list the specific files and changes needed, and offer to fix them

---

## Rules

- **Always spawn all three agents in parallel.** They are independent and run faster concurrently.
- **Always scope to changed files.** Pass the file list to all three agents — do not run full-codebase scans from this skill (the user can run the agents standalone for that). Exception: regression-analyzer's Check 4 (producer/consumer pair drift) does grep codebase-wide for matching subscribers — that's intentional and the agent handles it internally.
- **Deduplicate across agents.** The same violation should not appear three times in the report — prefer the regression-analyzer framing when behaviour is at stake.
- **Never auto-fix without confirmation.** Present findings first, then offer to fix.
- **Include the full check count.** Even if all checks pass, list them so the user knows what was verified.
