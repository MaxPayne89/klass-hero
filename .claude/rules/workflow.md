# Development Workflow

## GitHub Issues and Branching

1. Create a GitHub issue for the work item
2. Create a branch following pattern: `[type]/[issue-number]-[short-issue-description]`
   - Types: `fix`, `feature`, `design`, etc.
   - Example: `feature/123-user-authentication`
3. Work on the branch and create a Pull Request
4. PR should reference the issue (e.g., "Closes #123") for automatic closure

## Implementation References

When implementing features, reference:

- `.claude/rules/domain-architecture.md` - conventional-Phoenix conventions (schema-as-struct, bounded contexts) and key patterns
- Existing context implementations under `lib/klass_hero/<context>/` - Follow established patterns
- Existing LiveView pages - Established UI patterns and component usage

## Pre-commit Checklist

Before committing, always run:

```bash
mix precommit
```

This command:

1. Compiles with `--warning-as-errors` (treats warnings as errors)
2. Runs `mix deps.unlock --unused` (removes unused deps)
3. Runs `mix format` (auto-formats code)
4. Runs `mix test` (full test suite)

**Treat all warnings as errors** - the codebase maintains zero warnings.

## Merge Strategy

`main` keeps a **linear, one-commit-per-feature** history. Two rules enforce this:

1. **Rebase onto `main` before opening or updating a PR** — not merge. If your branch has fallen behind main:

   ```bash
   git fetch origin
   git rebase origin/main
   git push --force-with-lease
   ```

   Never use `git merge origin/main` inside a feature branch; it adds noisy merge commits to the branch and PR diff, makes future rebases harder, and clutters `git blame` walks during review.

2. **Squash-merge all PRs** — the "Squash and merge" button is the only merge button the UI exposes. The squashed commit message should use the semantic format from `CLAUDE.md`'s "Git Conventions" section (e.g. `feat: add staff invitation flow`). If the PR body has useful context, keep it in the squash-commit body; don't paste individual branch commits.

GitHub enforces both: `required_linear_history` on `main` rejects merge commits, and the repo settings + ruleset only allow squash-merge. Force pushes to `main` are blocked by `non_fast_forward`.

Inside a feature branch, commit as often as you like — those commits vanish into a single squash on merge.

## Important Notes

- No references to Claude Code in commits, issues, or PRs
- Project is for a non-professional product manager - be accommodating with requirements interpretation
- Merchant codes should be set under "sumup.merchant.code" attribute
