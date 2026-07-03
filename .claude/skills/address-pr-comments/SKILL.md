---
name: address-pr-comments
description: >-
  Fetch, triage, and address PR review comments for the current branch.
  Reads all comments from the PR, classifies each as actionable, nit, question,
  or dismissible, presents a structured assessment for confirmation, then plans
  and applies fixes. Use when: "address PR comments", "handle review feedback",
  "fix PR comments", "triage PR review", "respond to review", or after receiving
  PR review notifications. Invoke with /address-pr-comments.
---

# Address PR Comments

Fetch all PR review comments, triage them, get user confirmation, then plan and apply fixes.

**Type:** Rigid workflow. Follow steps exactly.

---

## Step 1: Detect PR

Auto-detect the PR for the current branch:

```bash
gh pr view --json number,title,url,state,headRefName,baseRefName,body
```

If no PR exists, STOP:
```
No PR found for current branch. Create one first with /create-pr.
```

Display: PR #number — title (state)

## Step 2: Fetch All Comments

Fetch every comment type on the PR:

```bash
# Review comments (line-level feedback from reviews)
gh api repos/{owner}/{repo}/pulls/{number}/comments --paginate

# Review bodies (top-level review summaries)
gh api repos/{owner}/{repo}/pulls/{number}/reviews --paginate

# Issue-style conversation comments
gh api repos/{owner}/{repo}/issues/{number}/comments --paginate
```

Parse each comment to extract:
- `id` — GitHub comment ID
- `author` — Who wrote it
- `body` — The comment text
- `path` — File path (for line-level comments, null for conversation)
- `line` — Line number (for line-level comments)
- `created_at` — Timestamp
- `in_reply_to` — Thread context
- `state` — PENDING, COMMENTED, APPROVED, CHANGES_REQUESTED, DISMISSED (for reviews)

Group threaded comments together. Exclude bot-generated comments (dependabot, etc.) unless they contain actionable content.

## Step 3: Triage and Classify

For each comment (or thread), read the referenced code and classify:

### Classification Categories

| Category | Meaning | Action |
|----------|---------|--------|
| `fix` | Valid issue requiring a code change | Plan and implement fix |
| `nit` | Style or preference suggestion, low priority | Apply if trivial, skip if opinionated |
| `question` | Reviewer asking for clarification | Respond with explanation |
| `outdated` | Comment on code that has already changed | Dismiss with note |
| `dismiss` | Invalid, misunderstanding, or bot noise | Dismiss with rationale |

### Effort Estimate

For `fix` and `nit` items, estimate effort:

| Effort | Meaning |
|--------|---------|
| `trivial` | 1-2 line change, no test impact |
| `small` | Under 20 lines, may need test update |
| `medium` | Multiple files or new tests needed |
| `large` | Architectural change, significant refactoring |

### Architecture Alignment Check

For each `fix` item, assess whether the proposed change aligns with:
- **Bounded contexts** — Does it respect context boundaries (cross-context calls via the `<context>.ex` root API only)?
- **Schema-as-struct** — Does it keep entity logic + persistence in the context module / entity module, without reintroducing repository/port layering?
- **Event-driven** — Does it preserve async communication patterns?
- **CQRS** — Does it keep read/write paths appropriately separated?

If a reviewer suggestion would violate these principles, classify as `dismiss` with architectural rationale, or propose an alternative fix that maintains alignment.

### Test Impact

For each `fix` item, note:
- Which existing tests might be affected
- Whether new tests are needed
- Whether integration tests need updating

## Step 4: Present Assessment

Display the triage summary for user confirmation. Use this exact format:

```markdown
# PR Comment Assessment — PR #[number]

**[title]** | [X] comments across [Y] threads

## Summary

| Category | Count | Effort Breakdown |
|----------|-------|-----------------|
| Fix      | N     | T trivial, S small, M medium, L large |
| Nit      | N     | T trivial, S small |
| Question | N     | — |
| Outdated | N     | — |
| Dismiss  | N     | — |

## Fixes Required

### F1: [Short description]
- **Comment:** [Author] on [file:line] — "[truncated quote]"
- **Classification:** fix | [effort]
- **Analysis:** [Why this needs fixing, what the correct approach is]
- **Architecture:** [convention alignment notes — bounded contexts, schema-as-struct, event-driven, CQRS — if relevant]
- **Test Impact:** [Which tests affected, new tests needed]
- **Proposed Change:** [Brief description of the fix]

### F2: ...

## Nits

### N1: [Short description]
- **Comment:** [Author] on [file:line] — "[truncated quote]"
- **Classification:** nit | [effort]
- **Recommendation:** Apply / Skip — [rationale]

## Questions

### Q1: [Short description]
- **Comment:** [Author] — "[truncated quote]"
- **Proposed Response:** [Draft reply]

## To Dismiss

### D1: [Short description]
- **Comment:** [Author] — "[truncated quote]"
- **Reason:** [Why this should be dismissed]
```

**STOP HERE.** Wait for user to:
1. Confirm the assessment as-is
2. Reclassify specific items (e.g., "F2 should be a nit", "D1 is actually valid")
3. Add context to items
4. Skip specific items

Do NOT proceed to fixes until user confirms.

## Step 5: Plan Fixes

After user confirmation, enter plan mode for all confirmed `fix` items.

Before planning:
1. **Invoke the `/idiomatic-elixir` skill** to load Elixir patterns and DDD guidance
2. **Invoke additional skills** as relevant to the fix:
   - Changes to events → architecture patterns are already loaded
   - Changes to LiveViews → check Phoenix/LiveView rules in `.claude/rules/`
   - Changes to tests → check testing rules in `.claude/rules/testing.md`

Plan all fixes together as a cohesive changeset. For each fix:
- Identify exact files and line ranges to modify
- Describe the change with code
- Note test files that need updating
- Ensure alignment with the conventions (bounded-context boundaries, schema-as-struct, event-driven, CQRS)

## Step 6: Apply Fixes

Execute the plan. For each fix:

1. Read the file (verify current state matches expectations)
2. Apply the change
3. Run relevant tests: `mix test [affected_test_file]`
4. If tests fail, diagnose and fix before moving on

Show progress: `Applying fix [N/total]: [description]`

After all fixes:

```bash
mix precommit
```

If precommit fails, fix issues before proceeding.

## Step 7: Respond to Questions

For each confirmed `question` item, draft a reply. Present all replies to user for confirmation before posting.

## Step 8: Commit, Push, and Resolve

```bash
git add [changed files]
git commit -m "fix: address PR review comments

[Summary of changes made]

Refs #[PR-number]"

git push
```

Then resolve comments on GitHub:

```bash
# For each addressed fix/nit comment thread
gh api repos/{owner}/{repo}/pulls/{pr}/comments/{id}/replies \
  -f body="Addressed in [commit-sha]."

# For each question
gh api repos/{owner}/{repo}/issues/{pr}/comments \
  -f body="[confirmed reply text]"

# For dismissed items (if user confirmed dismissal)
# Reply explaining why
gh api repos/{owner}/{repo}/pulls/{pr}/comments/{id}/replies \
  -f body="[dismissal rationale]"
```

## Step 9: Summary

Present final summary:

```markdown
# PR Comments Addressed

- **Fixes applied:** N
- **Nits applied:** N
- **Questions answered:** N
- **Dismissed:** N
- **Commit:** [sha]
- **All changes pushed:** yes/no
```

---

## Rules

- **Never apply fixes before user confirms the assessment.** The triage is a proposal, not a decision.
- **Always invoke `/idiomatic-elixir` before planning fixes.** Load architecture context first.
- **Always run `mix precommit` before committing.** Zero warnings, zero test failures.
- **Always push after committing.** Work is not done until pushed.
- **Respect architecture.** If a reviewer suggestion would violate the conventions (bounded-context boundaries, schema-as-struct, event-driven, CQRS), propose an alternative that maintains alignment rather than blindly applying the suggestion.
- **Consider test impact for every fix.** Note whether existing tests break, new tests are needed, or integration tests need updating.
- **Never dismiss without rationale.** Every dismissed comment gets a clear explanation.
- **Thread awareness.** Group related comments in the same thread — don't treat each reply as a separate item.
