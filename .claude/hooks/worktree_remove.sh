#!/usr/bin/env bash
# WorktreeRemove hook: tear down what the worktree was using before its directory
# disappears — its dev server, its dev database, its test database.
#
# This is what stops the next orphan. A dev server outlives `git worktree remove`
# perfectly happily: it keeps its port and keeps answering /tidewave/mcp for a
# checkout that no longer exists, which is worse than being down, because it looks
# healthy. One such process (a deleted kh-1321 worktree, still serving 4010) is what
# prompted this whole change.
#
# The event cannot block removal and its failures are only logged in debug mode, so
# this is best-effort by design. bin/worktree-up's reaper is the backstop for anything
# that slips through.
set -uo pipefail

PAYLOAD=$(cat | tr -d '\000-\037')
WORKTREE=$(jq -r '.worktree_path // empty' <<<"$PAYLOAD" 2>/dev/null)

[[ -n "$WORKTREE" && -d "$WORKTREE" ]] || exit 0
[[ -x "$WORKTREE/bin/worktree-down" ]] || exit 0

(cd "$WORKTREE" && bin/worktree-down >&2) || true

exit 0
