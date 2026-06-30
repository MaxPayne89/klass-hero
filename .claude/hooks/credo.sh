#!/usr/bin/env bash
# PostToolUse(Edit|Write) hook: run credo --strict on the edited Elixir file.
# asyncRewake contract: exit 2 (with output on stderr) wakes the session; exit 0 is silent.
set -uo pipefail

FILE=$(cat | tr -d '\000-\037' | jq -r '.tool_input.file_path // empty')

[[ -n "$FILE" ]] || exit 0
[[ "$FILE" =~ \.(ex|exs)$ ]] || exit 0
[[ -f "$FILE" ]] || exit 0

OUT=$(mix credo --strict "$FILE" 2>&1)
STATUS=$?

if [[ $STATUS -ne 0 ]]; then
  echo "mix credo --strict flagged ${FILE}:" >&2
  echo "$OUT" >&2
  exit 2
fi

exit 0
