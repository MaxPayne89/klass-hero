#!/usr/bin/env bash
# PostToolUse(Edit|Write) hook: run credo --strict on the edited Elixir file.
# asyncRewake contract: exit 2 (with output on stderr) wakes the session; exit 0 is silent.
set -uo pipefail

# A failed load has to be loud. Falling through would leave emit_untrusted
# undefined, so the call below would fail and the hook would exit 2 having
# printed no diagnostic at all — losing the very output it exists to deliver.
# shellcheck source=.claude/hooks/lib/untrusted.sh
if ! source "$(dirname "${BASH_SOURCE[0]}")/lib/untrusted.sh"; then
  echo "credo.sh: could not load lib/untrusted.sh — refusing to print unsanitised output" >&2
  exit 2
fi

FILE=$(cat | tr -d '\000-\037' | jq -r '.tool_input.file_path // empty')

[[ -n "$FILE" ]] || exit 0
[[ "$FILE" =~ \.(ex|exs)$ ]] || exit 0
[[ -f "$FILE" ]] || exit 0

OUT=$(mix credo --strict "$FILE" 2>&1)
STATUS=$?

if [[ $STATUS -ne 0 ]]; then
  echo "mix credo --strict flagged ${FILE}:" >&2
  emit_untrusted "mix credo --strict" "$OUT"
  exit 2
fi

exit 0
