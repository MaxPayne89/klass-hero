#!/usr/bin/env bash
# CwdChanged hook: when the session moves into a different checkout, make sure THAT
# checkout has a dev server, because it is the one bin/tidewave-router will forward to
# from now on.
#
# The router resolves its target from the session's current root on every call, so a
# mid-session EnterWorktree already repoints Tidewave correctly — nothing here has to
# fix the pointer. What it cannot do is start a server that was never started. This
# hook closes that gap: entering an existing, idle worktree brings it up.
#
# Deliberately does NOT export LOCAL_DEV_DATABASE or MIX_TEST_PARTITION into the
# session (via CLAUDE_ENV_FILE). config/dev.exs and config/test.exs derive both from
# the config file's own directory, so mix already resolves them correctly inside the
# worktree — and an export would outlive the move back to main, pointing main's mix at
# a worktree database. That is #1257 exactly, re-created by hand.
#
# Exit 0 always: a directory change is not worth failing.
set -uo pipefail

PAYLOAD=$(cat | tr -d '\000-\037')
NEW_CWD=$(jq -r '.new_cwd // empty' <<<"$PAYLOAD" 2>/dev/null)
OLD_CWD=$(jq -r '.old_cwd // empty' <<<"$PAYLOAD" 2>/dev/null)

[[ -d "$NEW_CWD" ]] || exit 0

checkout_of() {
  git -C "$1" rev-parse --show-toplevel 2>/dev/null
}

NEW_ROOT=$(checkout_of "$NEW_CWD")
OLD_ROOT=$(checkout_of "${OLD_CWD:-$NEW_CWD}")

# Moving around inside one checkout changes nothing about which server serves it.
[[ -n "$NEW_ROOT" && "$NEW_ROOT" != "$OLD_ROOT" ]] || exit 0
[[ -x "$NEW_ROOT/bin/worktree-status" ]] || exit 0

cd "$NEW_ROOT" || exit 0

if bin/worktree-status >/dev/null 2>&1; then
  exit 0
fi

mkdir -p .claude/run
nohup bin/worktree-up --quiet >>.claude/run/boot.log 2>&1 &
disown

jq -n --arg root "$NEW_ROOT" '{
  systemMessage: (
    "Entered \($root), which had no running dev server — provisioning started in the "
    + "background (log: .claude/run/boot.log). Tidewave already points here (the router "
    + "resolves the target per call); it will answer once the server is up. Check with "
    + "bin/worktree-status."
  )
}'

exit 0
