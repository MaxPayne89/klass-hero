#!/usr/bin/env bash
# PostToolUse(Edit|Write) hook: auto-format the edited Elixir/HEEx file.
# asyncRewake contract: exit 2 (with a message on stderr) wakes the session;
# exit 0 is silent. We only wake when the file was actually reformatted.
set -uo pipefail

# Read the hook payload. Strip raw control bytes (U+0000–U+001F) before jq —
# tool_response can carry unescaped ANSI/bell bytes that break strict jq parsing.
FILE=$(cat | tr -d '\000-\037' | jq -r '.tool_input.file_path // empty')

[[ -n "$FILE" ]] || exit 0
[[ "$FILE" =~ \.(ex|exs|heex)$ ]] || exit 0
[[ -f "$FILE" ]] || exit 0

# Already formatted? Nothing to do.
if mix format --check-formatted "$FILE" >/dev/null 2>&1; then
  exit 0
fi

if mix format "$FILE" >/dev/null 2>&1; then
  echo "mix format reformatted ${FILE} — re-read it before making further edits." >&2
  exit 2
fi

# Format itself errored (syntax error etc.) — stay silent; credo/compile will surface it.
exit 0
