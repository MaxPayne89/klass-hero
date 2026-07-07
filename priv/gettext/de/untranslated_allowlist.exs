# Msgids intentionally left untranslated in the German (de) catalog — they fall
# back to the English source string. Read by `mix lint_translations`, which would
# otherwise fail the build on an empty/fuzzy German `msgstr`.
#
# Every entry MUST have a one-line comment explaining WHY it stays English, so a
# reviewer can sanity-check it from the diff alone. Keep this list small: prefer a
# real translation over an allowlist entry. Keys are gettext text domains.
%{
  "default" => [
    # Brand name — never translated in any market.
    "Klass Hero"
  ],
  "enrollment" => [],
  "errors" => []
}
