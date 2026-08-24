#!/usr/bin/env bash
# WorktreeCreate hook: create the worktree AND provision it, so the session that
# lands in it already has its own databases and its own Tidewave port.
#
# This event replaces Claude Code's default `git worktree add`, so this script owns
# creation entirely. Its output contract is unusual and unforgiving:
#
#   * stdout must end with the absolute path of the created worktree, and nothing
#     else may be printed there. Every diagnostic goes to stderr.
#   * any non-zero exit aborts worktree creation.
#
# Provisioning is FULL — databases, seeds, and a running dev server — not --fast.
# --fast left the worktree without a server, which meant the first session to open here
# raced its own MCP connection: bin/tidewave-router would resolve the right checkout and
# find nothing listening. The hook budget is 600s and a warm worktree converges in ~30s,
# because bin/worktree-up copies deps/ and _build/ from the main checkout first.
#
# Deliberate deviation from "fail closed": a *provisioning* failure warns and still
# returns the path, because bin/worktree-up is convergent and SessionStart re-runs it.
# Only a failure to create the worktree itself aborts. Destroying a freshly created
# worktree over a transient docker hiccup would cost real work; a half-provisioned one
# costs a retry.
set -uo pipefail

PAYLOAD=$(cat | tr -d '\000-\037')
NAME=$(jq -r '.name // empty' <<<"$PAYLOAD" 2>/dev/null)

if [[ -z "$NAME" ]]; then
  echo "worktree_create: no .name in the hook payload" >&2
  exit 1
fi

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "worktree_create: not in a git repository" >&2
  exit 1
}
cd "$ROOT" || {
  echo "worktree_create: cannot cd to ${ROOT}" >&2
  exit 1
}

DEST="${ROOT}/.claude/worktrees/${NAME}"
BRANCH="worktree-${NAME}"

if [[ -d "$DEST" ]]; then
  echo "worktree_create: ${DEST} already exists" >&2
  exit 1
fi

git fetch origin --quiet 2>/dev/null || true

# Reuse the branch if it already exists; otherwise cut a fresh one from origin/main.
if git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
  git worktree add "$DEST" "$BRANCH" >&2 || exit 1
else
  git worktree add "$DEST" -b "$BRANCH" origin/main >&2 || exit 1
fi

if ! (cd "$DEST" && bin/worktree-up >&2); then
  cat >&2 <<EOF
worktree_create: ${NAME} was created but provisioning did not finish.
                 The worktree is usable; run bin/worktree-up inside it, or just start
                 a session there — the SessionStart hook retries automatically.
EOF
fi

# The contract: the path, alone, last.
echo "$DEST"
