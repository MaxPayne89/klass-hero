defmodule Mix.Tasks.LintTranslations do
  @shortdoc "Check gettext catalogs are in sync with source and DE translations are complete"
  @moduledoc """
  Two read-only checks (never writes `.po`/`.pot` files):

    1. **Structure** — runs `mix gettext.extract --check-up-to-date`, which fails
       if any `.pot` template would change (i.e. a `gettext(...)` call was
       added/removed/moved in source without re-extracting).

    2. **Completeness** — parses every non-default-locale `.po` file (currently
       `de`) with `Expo.PO` and fails on any message that is untranslated
       (empty `msgstr`) or still carries a `fuzzy` flag, unless its `msgid` is
       listed in the per-domain allowlist.

  The default locale (`en`) is intentionally excluded: it relies on Elixir's
  msgid-fallback and is expected to be empty.

  Intentional English passthroughs (e.g. brand names) are declared in the
  allowlist file `priv/gettext/de/untranslated_allowlist.exs`.

  ## Usage

      mix lint_translations
  """
  use Mix.Task

  alias Expo.Message.{Plural, Singular}

  @gettext_dir "priv/gettext"
  @allowlist_file "priv/gettext/de/untranslated_allowlist.exs"

  @impl true
  def run(_args) do
    Mix.Task.run("app.config")

    check_structure()
    check_completeness()
  end

  # --- Check 1: .pot templates in sync with source ---------------------------

  defp check_structure do
    # Raises Mix.Error on drift; a clean run returns normally.
    Mix.Task.run("gettext.extract", ["--check-up-to-date"])
  end

  # --- Check 2: DE catalogs complete and un-fuzzy ----------------------------

  defp check_completeness do
    locales = locales_to_check()
    allowlist = load_allowlist()

    violations =
      for locale <- locales,
          domain <- domains(),
          violation <- check_domain(locale, domain, allowlist) do
        violation
      end

    if violations == [] do
      Mix.shell().info("Translation completeness check passed for: #{Enum.join(locales, ", ")}.")
    else
      report(violations)
      Mix.raise("Translation check failed — #{length(violations)} untranslated/fuzzy msgid(s).")
    end
  end

  # Real locales that require translations = configured locales minus the
  # source/default locale. Derived from config so a 3rd locale is covered
  # automatically without editing this task.
  defp locales_to_check do
    config = Application.fetch_env!(:klass_hero, KlassHeroWeb.Gettext)
    Keyword.fetch!(config, :locales) -- [Keyword.fetch!(config, :default_locale)]
  end

  defp domains do
    @gettext_dir
    |> Path.join("*.pot")
    |> Path.wildcard()
    |> Enum.map(&Path.basename(&1, ".pot"))
    |> Enum.sort()
  end

  defp check_domain(locale, domain, allowlist) do
    path = Path.join([@gettext_dir, locale, "LC_MESSAGES", "#{domain}.po"])
    allowed = Map.get(allowlist, domain, MapSet.new())

    path
    |> Expo.PO.parse_file!()
    |> Map.fetch!(:messages)
    |> Enum.reject(& &1.obsolete)
    |> Enum.filter(&needs_translation?/1)
    |> Enum.reject(&(msgid_of(&1) in allowed))
    |> Enum.map(&{locale, domain, reason(&1), msgid_of(&1)})
  end

  # A message needs work if it is untranslated or fuzzy-flagged.
  defp needs_translation?(message) do
    empty?(message) or Expo.Message.has_flag?(message, "fuzzy")
  end

  # Singular: msgstr is one iodata string. Plural: msgstr is a map of
  # plural-form index => iodata; every form must be non-empty.
  defp empty?(%Singular{msgstr: msgstr}), do: blank?(msgstr)
  defp empty?(%Plural{msgstr: forms}), do: Enum.any?(forms, fn {_i, v} -> blank?(v) end)

  defp blank?(iodata), do: IO.iodata_to_binary(iodata) == ""

  defp reason(message) do
    cond do
      empty?(message) and Expo.Message.has_flag?(message, "fuzzy") -> "empty+fuzzy"
      empty?(message) -> "empty"
      true -> "fuzzy"
    end
  end

  defp msgid_of(message), do: IO.iodata_to_binary(message.msgid)

  # --- Allowlist -------------------------------------------------------------

  # File is an .exs term: %{"domain" => ["msgid", ...]}. Missing file => none.
  defp load_allowlist do
    if File.exists?(@allowlist_file) do
      {allowlist, _bindings} = Code.eval_file(@allowlist_file)
      Map.new(allowlist, fn {domain, msgids} -> {domain, MapSet.new(msgids)} end)
    else
      %{}
    end
  end

  # --- Reporting -------------------------------------------------------------

  defp report(violations) do
    Mix.shell().error(
      "Untranslated or fuzzy DE msgid(s) — add a translation (drop the fuzzy flag) " <>
        "or list the msgid in #{@allowlist_file}:\n"
    )

    Enum.each(violations, fn {locale, domain, reason, msgid} ->
      Mix.shell().error("  [#{locale}/#{domain}] (#{reason}) #{inspect(msgid)}")
    end)
  end
end
