#!/usr/bin/env bash
# PostToolUse(Edit|Write) hook: run typography lint when a HEEx template changes.
# asyncRewake contract: exit 2 (with output on stderr) wakes the session; exit 0 is silent.
set -uo pipefail

# A failed load has to be loud — see the note in credo.sh.
# shellcheck source=.claude/hooks/lib/untrusted.sh
if ! source "$(dirname "${BASH_SOURCE[0]}")/lib/untrusted.sh"; then
  echo "lint_typography.sh: could not load lib/untrusted.sh — refusing to print unsanitised output" >&2
  exit 2
fi

FILE=$(cat | tr -d '\000-\037' | jq -r '.tool_input.file_path // empty')

[[ -n "$FILE" ]] || exit 0
[[ "$FILE" =~ \.html\.heex$ ]] || exit 0
[[ -f "$FILE" ]] || exit 0

OUT=$(mix lint_typography 2>&1)
STATUS=$?

if [[ $STATUS -ne 0 ]]; then
  echo "mix lint_typography flagged a typography violation (edited ${FILE}):" >&2
  emit_untrusted "mix lint_typography" "$OUT"
  exit 2
fi

exit 0
