defmodule KlassHero.Shared.ErrorContextFilterTest do
  use ExUnit.Case, async: true

  alias KlassHero.Shared.ErrorContextFilter

  describe "sanitize/1 on Oban job args" do
    test "keeps correlation ids and the trace context" do
      context = %{
        "job.args" => %{
          "invite_id" => "inv-1",
          "user_id" => "usr-1",
          "program_id" => "prg-1",
          "trace_context" => %{"traceparent" => "00-abc-def-01"}
        }
      }

      assert %{"job.args" => args} = ErrorContextFilter.sanitize(context)

      assert args == %{
               "invite_id" => "inv-1",
               "user_id" => "usr-1",
               "program_id" => "prg-1",
               "trace_context" => %{"traceparent" => "00-abc-def-01"}
             }
    end

    # The reason this filter exists: ProcessInviteClaimWorker's args carry a child's
    # name, date of birth and medical conditions, and ErrorTracker persists context to
    # the production database on every failure.
    test "drops child identity and health fields" do
      context = %{
        "job.args" => %{
          "invite_id" => "inv-1",
          "child_first_name" => "Emma",
          "child_last_name" => "Schmidt",
          "child_date_of_birth" => "2016-03-15",
          "medical_conditions" => "Asthma",
          "nut_allergy" => true,
          "school_name" => "Berlin Elementary"
        }
      }

      assert %{"job.args" => args} = ErrorContextFilter.sanitize(context)

      assert Map.keys(args) == ["invite_id"]
    end

    # Key names are not PII, and an operator who cannot see that anything was removed
    # will read the surviving args as the whole story.
    test "records which keys were redacted, by name only" do
      context = %{"job.args" => %{"invite_id" => "inv-1", "medical_conditions" => "Asthma"}}

      assert %{"job.args.redacted" => redacted} = ErrorContextFilter.sanitize(context)
      assert redacted == ["medical_conditions"]
    end

    test "adds no redaction key when nothing was dropped" do
      context = %{"job.args" => %{"invite_id" => "inv-1"}}

      refute Map.has_key?(ErrorContextFilter.sanitize(context), "job.args.redacted")
    end
  end

  describe "sanitize/1 on everything else" do
    # The router sets user_id/email via ErrorTracker.set_context/1. Those are deliberate
    # and pre-date this filter; narrowing to job args must leave them alone.
    test "passes non-job context through untouched" do
      context = %{"job.queue" => "family", user_id: "usr-1", email: "parent@example.com"}

      assert ErrorContextFilter.sanitize(context) == context
    end

    test "leaves a non-map job.args alone" do
      context = %{"job.args" => "not-a-map"}

      assert ErrorContextFilter.sanitize(context) == context
    end
  end
end
