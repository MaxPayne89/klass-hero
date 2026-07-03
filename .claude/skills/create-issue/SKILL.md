---
name: create-issue
description: >-
  Create well-formed GitHub issues from findings, hypotheses, or gaps discovered during
  codebase exploration. Explores code to validate the finding, gathers references, classifies
  issue type (FEATURE/BUG/TASK), selects labels, drafts the body following project templates,
  and creates via gh CLI. Invoke with: `/create-issue "description of finding"`. Also triggers
  on "file an issue", "open an issue", "create a ticket", "turn this into an issue".
---

# Create Issue

Turn a finding or hypothesis into a well-formed GitHub issue with validated code references.

**Type:** Rigid workflow. Follow steps exactly.

---

## Step 1: Parse Input

Extract the hypothesis/finding from:
1. The skill argument (e.g., `/create-issue "session creation not in UI"`)
2. The current conversation context (recent exploration results)

If neither provides a clear finding, ask the user to describe it.

Formulate a one-sentence hypothesis: what exists, what's missing, or what's broken.

## Step 2: Check for Duplicates

Search for existing issues that already cover this finding:

```bash
gh issue list --search "keyword1 keyword2" --state open --json number,title,labels --limit 10
```

Use 2-3 key terms from the hypothesis. If a matching open issue exists, show it to the user and stop unless they want a new issue anyway.

## Step 3: Validate Hypothesis

Explore the codebase to confirm or disprove the finding. Use Grep, Glob, and Read to gather evidence.

Classify the finding:

| Classification | Meaning | Action |
|---|---|---|
| `confirmed-gap` | Finding validated — functionality missing or broken | Continue to Step 4 |
| `partially-exists` | Some pieces exist, others missing | Continue — scope issue to the gap |
| `already-exists` | Functionality exists, finding invalid | Show evidence, stop |
| `not-applicable` | Finding doesn't apply to this codebase | Explain why, stop |

Present classification with evidence (file paths, code snippets) to the user before continuing.

## Step 4: Gather Code References

Collect everything useful for the issue:

- **Relevant files** — paths and line numbers for existing related code
- **Bounded context** — which context this belongs to (explore `lib/klass_hero/<context>/` to identify)
- **Existing patterns** — similar implementations to follow as reference
- **Dependencies** — prerequisites or related issues

## Step 5: Determine Type, Labels, and Draft

### Issue Type

| Finding nature | Type prefix | Default label |
|---|---|---|
| Missing functionality, new capability | `[FEATURE]` | `enhancement` |
| Broken behavior, regression, incorrect output | `[BUG]` | `bug` |
| Refactor, cleanup, infra, chore | `[TASK]` | (context-dependent) |

**Important:** The repo uses `enhancement` for features — there is no `feature` label.

### Labels

Select labels from the repo taxonomy. See `references/labels.md` for the full list and selection guidance. Always pick:
1. One **type** label (`enhancement`, `bug`, `refactor`, etc.)
2. One **area** label if applicable (`backend`, `mobile`, `admin-dashboard`, `api`, `docs`)
3. One **priority** label if severity is clear (`priority:high`, `priority:medium`, `priority:low`)
4. One **epic** label if it maps to a strategic initiative

### Draft Issue Body

Use the matching template from `references/templates.md`. Fill in all sections with the validated findings and code references from Steps 3-4.

### Present for Review

Show the user the complete draft:
- Title (with type prefix)
- Labels
- Full body

**Do NOT create the issue before user confirmation.** Let the user adjust title, labels, body, or cancel.

## Step 6: Create Issue

On user approval:

```bash
gh issue create \
  --title "[TYPE] Title here" \
  --body "$(cat <<'EOF'
Body content here...
EOF
)" \
  --label "label1,label2" \
  --assignee "MaxPayne89"
```

Capture the issue URL from stdout.

## Step 7: Link to Project

Attempt to add the issue to the klass-hero GitHub project:

```bash
# Find the project number
gh project list --owner MaxPayne89 --format json

# Add issue to project (requires read:project scope)
gh project item-add <PROJECT_NUMBER> --owner MaxPayne89 --url <ISSUE_URL>
```

If this fails due to missing `read:project` token scope, inform the user:

```
Project linking failed (token missing read:project scope).
Manual step: go to the issue on GitHub and add it to the project board.
```

Output the created issue URL.

---

## Rules

- **Never create without confirmation.** Present the full draft for user review first.
- **Validate before drafting.** Always check the codebase — never file issues based on assumptions.
- **Check for duplicates.** Search existing open issues before drafting.
- **Use `enhancement`, not `feature`.** The repo's feature label is `enhancement`.
- **Always assign to MaxPayne89.**
- **Include code references.** Every issue body must have file paths and relevant context.
- **Keep titles under 80 characters** (excluding the type prefix).
- **Use HEREDOC for body.** Pass multi-line body via `cat <<'EOF'` to preserve formatting.
