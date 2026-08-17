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

  describe "sanitize/1 on captured params" do
    # The exact shape recorded in production when the #1322 crash hit
    # ChildrenLive's "save_child": the guardian's whole form, health fields included.
    test "replaces a nested form map with its key names" do
      context = %{
        "live_view.event" => "save_child",
        "live_view.event_params" => %{
          "child" => %{
            "first_name" => "Louis",
            "last_name" => "Davids",
            "date_of_birth" => "2017-03-15",
            "allergies" => "none",
            "support_needs" => "none",
            "emergency_contact" => "0163-194 5369",
            "gender" => "male",
            "school_grade" => "4"
          },
          "consent" => "true"
        }
      }

      assert %{"live_view.event_params" => params} = ErrorContextFilter.sanitize(context)

      assert params["child"] ==
               "[8 keys redacted: allergies, date_of_birth, emergency_contact, first_name, " <>
                 "gender, last_name, school_grade, support_needs]"
    end

    # Which fields were submitted is the debugging signal; what was in them is the PII.
    # Losing the consent flag would have cost us the only proof the box was ticked.
    test "keeps allowlisted scalars so a crash is still diagnosable" do
      context = %{
        "live_view.event_params" => %{
          "consent" => "true",
          "child_id" => "616fd5e9",
          "_target" => ["child", "allergies"]
        }
      }

      assert %{"live_view.event_params" => params} = ErrorContextFilter.sanitize(context)

      assert params == %{
               "consent" => "true",
               "child_id" => "616fd5e9",
               "_target" => ["child", "allergies"]
             }
    end

    test "redacts a top-level scalar that is not allowlisted, keeping its key" do
      context = %{"live_view.event_params" => %{"email" => "parent@example.com"}}

      assert %{"live_view.event_params" => params} = ErrorContextFilter.sanitize(context)
      assert params == %{"email" => "[redacted]"}
    end

    # sanitize/1 runs once on the merged context at report time, so a LiveView crash can
    # carry mount, handle_params and handle_event params at once — plus request.params
    # when the dead render went through the router first.
    test "narrows every params key present in one context" do
      sensitive = %{"child" => %{"allergies" => "none"}}

      context = %{
        "live_view.params" => sensitive,
        "live_view.event_params" => sensitive,
        "request.params" => sensitive
      }

      sanitized = ErrorContextFilter.sanitize(context)

      for key <- ["live_view.params", "live_view.event_params", "request.params"] do
        assert sanitized[key]["child"] == "[1 keys redacted: allergies]"
      end
    end

    test "leaves an empty params map alone" do
      context = %{"live_view.event_params" => %{}}

      assert ErrorContextFilter.sanitize(context) == context
    end

    # request.params is nil until Plug fetches it; live_view.event_params is absent
    # entirely on a mount crash. Neither may raise.
    test "leaves a non-map params value alone" do
      context = %{"request.params" => nil, "live_view.event_params" => "unfetched"}

      assert ErrorContextFilter.sanitize(context) == context
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

    # The two halves are independent: an Oban failure has no params, a LiveView crash has
    # no job args, and a filter that only handled one of them is what produced #1391.
    test "narrows job args and params in the same context" do
      context = %{
        "job.args" => %{"invite_id" => "inv-1", "medical_conditions" => "Asthma"},
        "live_view.event_params" => %{"child" => %{"allergies" => "none"}}
      }

      sanitized = ErrorContextFilter.sanitize(context)

      assert sanitized["job.args"] == %{"invite_id" => "inv-1"}
      assert sanitized["job.args.redacted"] == ["medical_conditions"]
      assert sanitized["live_view.event_params"]["child"] == "[1 keys redacted: allergies]"
    end
  end
end
