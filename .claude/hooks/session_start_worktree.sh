#!/usr/bin/env bash
# SessionStart(startup|resume) hook: make sure this checkout has a dev server and a
# Tidewave endpoint that belong to it, before the session does any work.
#
# This is the load-bearing path. WorktreeCreate is an accelerator that only fires for
# harness-created worktrees; this fires for every session in every checkout, however
# that checkout came to exist, so a session can never quietly begin against a dead or
# foreign Tidewave.
#
# Fast when there is nothing to do (a status check is two lsof calls and a curl), so
# the common case costs nothing. Provisioning only runs when the check fails, and is
# detached so a cold compile cannot hold up the session.
#
# Exit 0 always: a provisioning problem is worth reporting, never worth refusing to
# start a session over.
set -uo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[[ -x bin/worktree-status ]] || exit 0

if bin/worktree-status >/dev/null 2>&1; then
  exit 0
fi

STATUS=$(bin/worktree-status 2>&1 || true)

# Detached: a cold checkout needs deps + compile, which can outlast any hook budget.
# The session starts now and the server catches up.
mkdir -p .claude/run
nohup bin/worktree-up --quiet >>.claude/run/boot.log 2>&1 &
disown

cat >&2 <<EOF
Dev server / Tidewave was not ready for this checkout — provisioning started in the
background (log: .claude/run/boot.log). Check with: bin/worktree-status

$STATUS

Until it reports READY, do not rely on Tidewave: follow the Unavailability Alert
Protocol in .claude/rules/mcp-integration.md rather than silently falling back to bash.
If .mcp.json was only just written, this session cannot pick it up at all — it is read
at session start. Restart the session here once bin/worktree-status says READY.
EOF

exit 0
