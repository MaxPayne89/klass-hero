defmodule KlassHero.Shared.ErrorReportingTest do
  # `config/test.exs` disables ErrorTracker so the suite's deliberate Oban failures do not
  # write error rows. This is the one test that turns it back on: everything else here is
  # unit-tested against the filter and the shim directly, but nothing else proves that a real
  # `ErrorTracker.report/3` lands narrowed in both tables.
  use KlassHero.DataCase, async: false

  alias ErrorTracker.Occurrence

  @stacktrace [{KlassHero.Family, :create_child, 2, [file: "lib/klass_hero/family.ex", line: 42]}]

  setup do
    previous = Application.get_env(:error_tracker, :enabled)
    Application.put_env(:error_tracker, :enabled, true)
    on_exit(fn -> Application.put_env(:error_tracker, :enabled, previous) end)

    :ok
  end

  test "a reported exception stores no interpolated user data in either table" do
    exception = %KeyError{
      key: :program_id,
      term: %{"body" => "Hallo, der Kurs faellt aus", "staff" => "Anna Muster"}
    }

    occurrence = ErrorTracker.report(exception, @stacktrace)

    assert occurrence.reason == "key :program_id not found in: [redacted]"

    stored_error = Repo.get!(ErrorTracker.Error, occurrence.error_id)
    stored_occurrence = Repo.get!(Occurrence, occurrence.id)

    for row <- [stored_error, stored_occurrence], leaked <- ["Anna Muster", "Kurs faellt aus"] do
      refute row.reason =~ leaked
    end

    assert stored_error.kind == "Elixir.KeyError"
  end

  test "narrowing the reason does not move the fingerprint" do
    # Error.new/3 hashes kind + source_line + source_function and deliberately excludes
    # reason. prod-watch dedups on that fingerprint and stamps it into the issues it files,
    # so a fix that shifted it would orphan every already-filed issue.
    exception = %KeyError{key: :program_id, term: %{"email" => "anna@example.de"}}

    {:ok, stacktrace} = ErrorTracker.Stacktrace.new(@stacktrace)

    {:ok, unnarrowed} =
      ErrorTracker.Error.new("Elixir.KeyError", Exception.message(exception), stacktrace)

    occurrence = ErrorTracker.report(exception, @stacktrace)

    assert Repo.get!(ErrorTracker.Error, occurrence.error_id).fingerprint ==
             unnarrowed.fingerprint
  end
end
