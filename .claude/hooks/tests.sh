#!/usr/bin/env bash
# PostToolUse(Edit|Write) hook: run the test file(s) relevant to the edited file.
# asyncRewake contract: exit 2 (with output on stderr) wakes the session; exit 0 is silent.
#
# Target derivation (exact 1:1 path-swap only):
#   lib/<rel>/<name>.ex        -> test/<rel>/<name>_test.exs
#   lib/<rel>/<name>.html.heex -> test/<rel>/<name>_test.exs
#   test/<rel>/<name>_test.exs -> itself
# No matching test file -> silent (exit 0).
#
# A stem-prefix glob was tried and rejected: filename prefixes can't tell a
# qualifier ("child" -> "child_guardian") from a sibling module, so it both
# over-matched (running unrelated tests) and under-matched the multi-file
# LiveViews it was meant to catch. 1:1 is the only unambiguous mapping.
set -uo pipefail

# A failed load has to be loud — see the note in credo.sh.
# shellcheck source=.claude/hooks/lib/untrusted.sh
if ! source "$(dirname "${BASH_SOURCE[0]}")/lib/untrusted.sh"; then
  echo "tests.sh: could not load lib/untrusted.sh — refusing to print unsanitised output" >&2
  exit 2
fi

FILE=$(cat | tr -d '\000-\037' | jq -r '.tool_input.file_path // empty')
[[ -n "$FILE" ]] || exit 0

# Make the path repo-relative (hook payload paths are absolute; cwd is the project root).
REL="${FILE#"$PWD"/}"

declare -a PATHS=()

if [[ "$REL" == test/*_test.exs ]]; then
  # Editing a test directly — run it.
  [[ -f "$REL" ]] && PATHS+=("$REL")
elif [[ "$REL" == lib/* ]]; then
  STEM="${REL#lib/}"
  case "$STEM" in
    *.html.heex) BASE="${STEM%.html.heex}" ;;
    *.ex)        BASE="${STEM%.ex}" ;;
    *)           exit 0 ;;
  esac
  DIR="test/$(dirname "$BASE")"
  NAME="$(basename "$BASE")"
  PRIMARY="${DIR}/${NAME}_test.exs"
  [[ -f "$PRIMARY" ]] && PATHS+=("$PRIMARY")
else
  exit 0
fi

[[ ${#PATHS[@]} -gt 0 ]] || exit 0

# CI=true skips the Docker test.setup branch in the repo's test alias (assumes Postgres is up).
OUT=$(CI=true mix test "${PATHS[@]}" --max-failures 5 2>&1)
STATUS=$?
[[ $STATUS -eq 0 ]] && exit 0

# Couldn't run (Postgres down / DB unreachable) is not a test failure — stay silent.
if echo "$OUT" | grep -qiE 'could not connect|connection refused|DBConnection\.ConnectionError|no such (file|database)'; then
  exit 0
fi

echo "Tests failed for ${REL} (${PATHS[*]}):" >&2
emit_untrusted "mix test ${PATHS[*]}" "$OUT"
exit 2
