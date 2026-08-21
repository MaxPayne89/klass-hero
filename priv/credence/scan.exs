# Runs Credence over this project's source.
#
# Credence ships no project-wide mix task — its public API (`Credence.analyze/2`,
# `Credence.fix/2`) takes a source *string* — so walking files is our job. This is
# a script rather than a `lib/mix/tasks/*.ex` on purpose: `elixirc_paths` compiles
# `lib/` in every env, so a task referencing a `only: [:dev, :test]` dep would warn
# "module Credence is not available" on every prod build. `.exs` is never compiled.
#
#     mix run --no-start priv/credence/scan.exs                    # report, writes nothing
#     mix run --no-start priv/credence/scan.exs --fix              # rewrite in place
#     mix run --no-start priv/credence/scan.exs --rules NoSortThenReverse,NoDoubleReverse
#     mix run --no-start priv/credence/scan.exs test/klass_hero    # explicit paths
#
# `--no-start` keeps the app unbooted, so no Repo connection and no dev DB needed.
#
# Assumptions default to `:strict`, which disables the four rules gated on
# `single_codepoint_graphemes` / `proper_lists`. Those rewrites are only equivalent
# for single-piece characters, and we handle German content, user-entered names and
# emoji in messages. `--assumptions default` re-enables them.
#
# Exits non-zero when anything is reported, so it can gate CI later.

defmodule Credence.Scan do
  @default_paths ["lib/**/*.ex"]
  @top_files 20

  def main(argv) do
    {opts, paths} = parse(argv)

    files =
      case paths do
        [] -> @default_paths
        given -> Enum.map(given, &expand/1)
      end
      |> Enum.flat_map(&Path.wildcard/1)
      |> Enum.uniq()
      |> Enum.sort()

    if files == [], do: abort("No files matched.")

    IO.puts("Scanning #{length(files)} file(s) with #{length(Credence.enabled_rules(opts))} rule(s)...\n")

    if opts[:fix], do: fix(files, opts), else: analyze(files, opts)
  end

  # -- modes ----------------------------------------------------------------

  defp analyze(files, opts) do
    {results, errors} = walk(files, &Credence.analyze(&1, opts))

    findings =
      for {file, _source, %{issues: issues}} <- results,
          issue <- issues,
          do: {file, issue}

    report_errors(errors)

    if findings == [] do
      IO.puts("Credence found nothing.")
      halt(errors)
    else
      report_by_rule(findings)
      report_by_file(findings)
      IO.puts("\n#{length(findings)} finding(s) across #{count_files(findings)} file(s).")
      IO.puts("Nothing was written. Re-run with --fix (optionally --rules ...) to apply.")
      System.halt(1)
    end
  end

  defp fix(files, opts) do
    {results, errors} = walk(files, &Credence.fix(&1, opts))

    changed =
      for {file, source, %{code: code, applied_rules: applied}} <- results, code != source do
        File.write!(file, code)
        {file, applied}
      end

    report_errors(errors)

    Enum.each(changed, fn {file, applied} ->
      IO.puts("  #{file}")
      Enum.each(applied, fn {rule, count} -> IO.puts("      #{short(rule)} x#{count}") end)
    end)

    IO.puts("\n#{length(changed)} file(s) rewritten.")
    IO.puts("Run `mix format` next — Quokka reshapes what sourceror emits — then `mix precommit`.")
    halt(errors)
  end

  # -- walking --------------------------------------------------------------

  # A file Credence cannot process is a finding in its own right, not something to
  # swallow: it means a whole file went unchecked.
  defp walk(files, fun) do
    {ok, errors} =
      Enum.reduce(files, {[], []}, fn file, {ok, errors} ->
        source = File.read!(file)

        try do
          {[{file, source, fun.(source)} | ok], errors}
        rescue
          e -> {ok, [{file, Exception.message(e)} | errors]}
        end
      end)

    {Enum.reverse(ok), Enum.reverse(errors)}
  end

  # -- reporting ------------------------------------------------------------

  defp report_by_rule(findings) do
    IO.puts("By rule:\n")

    findings
    |> Enum.group_by(fn {_file, issue} -> issue.rule end)
    |> Enum.sort_by(fn {_rule, hits} -> -length(hits) end)
    |> Enum.each(fn {rule, hits} ->
      IO.puts("  #{pad(length(hits))}  #{rule}  (#{count_files(hits)} file(s))")
    end)
  end

  defp report_by_file(findings) do
    by_file =
      findings
      |> Enum.group_by(fn {file, _issue} -> file end)
      |> Enum.sort_by(fn {_file, hits} -> -length(hits) end)

    IO.puts("\nTop #{@top_files} files:\n")

    for {file, hits} <- Enum.take(by_file, @top_files) do
      IO.puts("  #{pad(length(hits))}  #{file}")

      hits
      |> Enum.sort_by(fn {_file, issue} -> issue.meta[:line] || 0 end)
      |> Enum.each(fn {_file, issue} -> IO.puts("         #{file}:#{issue.meta[:line]}: #{issue.rule}") end)
    end

    dropped = length(by_file) - @top_files
    if dropped > 0, do: IO.puts("\n  ... and #{dropped} more file(s) with findings.")
  end

  defp report_errors([]), do: :ok

  defp report_errors(errors) do
    IO.puts("Credence could not process #{length(errors)} file(s) — these went UNCHECKED:\n")
    Enum.each(errors, fn {file, message} -> IO.puts("  #{file}: #{message}") end)
    IO.puts("")
  end

  defp count_files(findings), do: findings |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> length()

  defp pad(count), do: String.pad_leading(to_string(count), 5)

  # -- options --------------------------------------------------------------

  defp parse(argv) do
    {parsed, paths, invalid} =
      OptionParser.parse(argv,
        strict: [fix: :boolean, rules: :string, assumptions: :string, verbose: :boolean]
      )

    if invalid != [], do: abort("Unknown option(s): #{inspect(Enum.map(invalid, &elem(&1, 0)))}")

    if !parsed[:verbose], do: Logger.configure(level: :warning)

    opts =
      [assumptions: assumptions(parsed[:assumptions])] ++
        List.wrap(parsed[:fix] && {:fix, true}) ++
        List.wrap(parsed[:rules] && {:rules, resolve_rules(parsed[:rules])})

    {opts, paths}
  end

  defp assumptions(nil), do: :strict
  defp assumptions("strict"), do: :strict
  defp assumptions("default"), do: :default
  defp assumptions(other), do: abort(~s|--assumptions must be "strict" or "default", got #{inspect(other)}|)

  # `rules:` takes rule *modules*; the friendly names are what `rule_status/1`
  # reports, so resolve through it rather than making callers type module names.
  defp resolve_rules(csv) do
    known = Map.new(Credence.rule_status([]), &{&1.name, &1.rule})

    csv
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(fn name ->
      Map.get(known, name) ||
        abort("Unknown rule #{inspect(name)}. Known: #{known |> Map.keys() |> Enum.sort() |> Enum.join(", ")}")
    end)
  end

  # A bare directory means "everything Elixir under it".
  defp expand(path), do: if(File.dir?(path), do: Path.join(path, "**/*.{ex,exs}"), else: path)

  defp short(rule), do: rule |> Module.split() |> List.last()

  defp halt([]), do: :ok
  defp halt(_errors), do: System.halt(1)

  defp abort(message) do
    IO.puts(:stderr, message)
    System.halt(2)
  end
end

Credence.Scan.main(System.argv())
