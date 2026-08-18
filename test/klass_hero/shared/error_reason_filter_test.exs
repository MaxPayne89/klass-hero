defmodule KlassHero.Shared.ErrorReasonFilterTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias KlassHero.Shared.ErrorReasonFilter

  @unrecognised "[reason redacted: unrecognised message shape]"

  # Every input is built with Exception.message/1 rather than hand-written, so an Elixir
  # upgrade that reshapes exception messages fails these tests loudly instead of silently
  # reopening the leak.
  @payload %{"email" => "anna@example.de", "staff" => "Anna Muster"}

  # Payload below the fold: a safe clause, a blank line, then the interpolated term.
  @separated [
    {"KeyError", Exception.message(%KeyError{key: :program_id, term: @payload}),
     "key :program_id not found in: [redacted]"},
    {"MatchError", Exception.message(%MatchError{term: {:error, @payload}}),
     "no match of right hand side value: [redacted]"},
    {"CaseClauseError", Exception.message(%CaseClauseError{term: @payload}), "no case clause matching: [redacted]"},
    {"Protocol.UndefinedError",
     Exception.message(%Protocol.UndefinedError{
       protocol: Enumerable,
       value: @payload,
       description: ""
     }), "protocol Enumerable not implemented for Map [redacted]"},
    {"Postgrex.Error, whose detail names the offending value",
     Exception.message(%Postgrex.Error{
       postgres: %{
         code: :unique_violation,
         message: "duplicate key value violates unique constraint \"users_email_index\"",
         detail: "Key (email)=(anna@example.de) already exists.",
         severity: "ERROR",
         pg_code: "23505"
       }
     }),
     "ERROR 23505 (unique_violation) duplicate key value violates unique constraint \"users_email_index\" [redacted]"},
    {"Ecto.ConstraintError", "constraint error when attempting to insert struct:\n\n    * \"x\" (unique_constraint)",
     "constraint error when attempting to insert struct: [redacted]"}
  ]

  # Payload on the same line as the clause — nothing structural separates the two, so these
  # are judged against the allowlist.
  @inline [
    {"Oban.PerformError keeps its worker",
     Exception.message(Oban.PerformError.exception({KlassHero.Family, {:error, @payload}})),
     "KlassHero.Family failed with [redacted]"},
    {"ArgumentError interpolating into its own message",
     Exception.message(%ArgumentError{message: "bad value #{inspect(@payload)}"}), @unrecognised},
    {"Oban.CrashError, which banners an arbitrary exception",
     Exception.message(
       Oban.CrashError.exception({:error, %ArgumentError{message: "bad value #{inspect(@payload)}"}, []})
     ), @unrecognised},
    {"an exit term, which can be any value at all", inspect({:shutdown, @payload}), @unrecognised}
  ]

  # Recognised shapes that carry nothing, and so survive whole.
  @intact [
    {"FunctionClauseError",
     Exception.message(%FunctionClauseError{
       module: KlassHero.Family,
       function: :create_child,
       arity: 2
     }), "no function clause matching in KlassHero.Family.create_child/2"},
    {"KeyError raised without a term", Exception.message(%KeyError{key: :program_id, term: nil}),
     "key :program_id not found"},
    {"Oban.TimeoutError", Exception.message(Oban.TimeoutError.exception({KlassHero.Family, 5000})),
     "KlassHero.Family timed out after 5000ms"}
  ]

  describe "sanitize/1" do
    test "keeps the clause and drops the term rendered below it" do
      for {name, reason, expected} <- @separated do
        assert ErrorReasonFilter.sanitize(reason) == expected, "#{name} was not narrowed"
      end
    end

    test "redacts a payload rendered inline, keeping only what the allowlist recognises" do
      for {name, reason, expected} <- @inline do
        assert ErrorReasonFilter.sanitize(reason) == expected, "#{name} was not narrowed"
      end
    end

    test "leaves a recognised message that carries no payload untouched" do
      for {name, reason, expected} <- @intact do
        assert ErrorReasonFilter.sanitize(reason) == expected, "#{name} should have survived"
      end
    end
  end

  # The two rows found in production, kept as named tests because their value is the shape,
  # not the rule: this is what #1398 was filed for.
  describe "sanitize/1 on the reasons found in production" do
    test "drops the message text and staff name a KeyError had rendered" do
      reason =
        Exception.message(%KeyError{
          key: :program_id,
          term: %{"body" => "Hallo, der Kurs faellt aus", "staff" => "Anna Muster"}
        })

      sanitized = ErrorReasonFilter.sanitize(reason)

      assert sanitized == "key :program_id not found in: [redacted]"
      refute sanitized =~ "Anna Muster"
    end

    test "drops the email address a MatchError had rendered" do
      reason = Exception.message(%MatchError{term: {:error, %{"email" => "anna@example.de"}}})

      sanitized = ErrorReasonFilter.sanitize(reason)

      assert sanitized == "no match of right hand side value: [redacted]"
      refute sanitized =~ "anna@example.de"
    end
  end

  describe "sanitize/1 invariants" do
    property "nothing below the first line survives, whatever a future exception renders" do
      heads = for {_name, reason, _expected} <- @separated, do: hd(String.split(reason, "\n"))

      check all(
              head <- member_of(heads),
              payload <- string(:alphanumeric, min_length: 20, max_length: 60)
            ) do
        assert ErrorReasonFilter.sanitize(head <> "\n\n    " <> payload) == head <> " [redacted]"
      end
    end

    property "the result is always a single line" do
      check all(reason <- string(:printable, min_length: 1, max_length: 200)) do
        refute ErrorReasonFilter.sanitize(reason) =~ "\n"
      end
    end
  end
end
