defmodule KlassHero.Shared.ErrorContextFilterTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias KlassHero.Shared.ErrorContextFilter

  @param_keys ~w(live_view.event_params live_view.params request.params)

  # Every generated value the filter is supposed to destroy carries this prefix, so a single
  # substring check over the whole sanitized context is a complete oracle for "nothing leaked".
  @pii_prefix "pii-"

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

  # The report path calls sanitize/1 exactly once, so idempotence never mattered until
  # #1406 added a second caller: a migration narrowing the rows written before this filter
  # existed, which necessarily also meets rows the filter has already narrowed.
  describe "sanitize/1 on already-narrowed context" do
    # Without this, a second pass sees a string rather than a map and collapses the marker
    # to "[redacted]" — destroying the field names that are the whole point of the params half.
    test "keeps a nested marker instead of collapsing it to the scalar marker" do
      context = %{
        "live_view.event_params" => %{
          "child" => %{"first_name" => "Louis", "allergies" => "none"}
        }
      }

      once = ErrorContextFilter.sanitize(context)

      assert once["live_view.event_params"]["child"] == "[2 keys redacted: allergies, first_name]"
      assert ErrorContextFilter.sanitize(once) == once
    end

    test "keeps a scalar marker" do
      once = ErrorContextFilter.sanitize(%{"request.params" => %{"email" => "a@example.com"}})

      assert once["request.params"] == %{"email" => "[redacted]"}
      assert ErrorContextFilter.sanitize(once) == once
    end

    test "is idempotent across both halves of one context" do
      context = %{
        "job.args" => %{"invite_id" => "inv-1", "medical_conditions" => "Asthma"},
        "live_view.event_params" => %{"child" => %{"allergies" => "none"}, "email" => "a@b.c"}
      }

      once = ErrorContextFilter.sanitize(context)

      assert ErrorContextFilter.sanitize(once) == once
    end

    # The cost of recognising the marker by its shape: a value the user typed that happens to
    # look like one survives verbatim. Bounded on purpose — the regex is anchored to the exact
    # string nested_marker/1 emits, and no plausible PII (a name, a date, an allergy) matches it.
    # Only a structural marker could close this, and that would change the shape every stored
    # context is read in.
    test "passes through a user-submitted string shaped like a marker" do
      context = %{"live_view.event_params" => %{"note" => "[2 keys redacted: a, b]"}}

      assert %{"live_view.event_params" => params} = ErrorContextFilter.sanitize(context)
      assert params["note"] == "[2 keys redacted: a, b]"
    end

    # ...but only that exact shape. Anything merely resembling it is still redacted.
    test "redacts a string that only resembles a marker" do
      context = %{
        "live_view.event_params" => %{
          "a" => "[keys redacted: allergies]",
          "b" => "see [2 keys redacted: x, y]",
          "c" => "[2 keys redacted: x, y] and more"
        }
      }

      assert %{"live_view.event_params" => params} = ErrorContextFilter.sanitize(context)
      assert params == %{"a" => "[redacted]", "b" => "[redacted]", "c" => "[redacted]"}
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

  describe "sanitize/1 properties" do
    property "is a fixpoint — narrowing an already-narrowed context changes nothing" do
      check all(context <- context_gen()) do
        once = ErrorContextFilter.sanitize(context)

        assert ErrorContextFilter.sanitize(once) == once
      end
    end

    # Closed by default, over generated input rather than the named fields of the example
    # tests: whatever a new worker or a new form adds, its values do not reach the error store.
    property "no value the filter is meant to destroy survives" do
      check all(context <- context_gen()) do
        sanitized = context |> ErrorContextFilter.sanitize() |> Jason.encode!()

        refute sanitized =~ @pii_prefix
      end
    end
  end

  defp context_gen do
    gen all(
          args <- one_of([args_gen(), constant(nil), constant("not-a-map")]),
          params <- submap_gen(@param_keys, params_gen()),
          passthrough <- map_of(name_gen(), string(:alphanumeric), max_length: 2)
        ) do
      params
      |> Map.put("job.args", args)
      |> Map.merge(passthrough)
    end
  end

  defp args_gen do
    gen all(
          allowed <- submap_gen(allowed_args(), safe_value_gen()),
          dropped <- map_of(name_gen(), pii_value_gen(), max_length: 3)
        ) do
      Map.merge(dropped, allowed)
    end
  end

  defp params_gen do
    gen all(
          allowed <- submap_gen(allowed_params(), safe_value_gen()),
          redacted <-
            map_of(name_gen(), one_of([pii_value_gen(), nested_gen()]), max_length: 3)
        ) do
      Map.merge(redacted, allowed)
    end
  end

  defp nested_gen, do: map_of(name_gen(), pii_value_gen(), max_length: 4)

  # Each key is independently present or absent. `map_of(member_of(keys), ...)` would be the
  # obvious spelling and is a trap: it draws *unique* keys from a handful of terms and dies with
  # StreamData.TooManyDuplicatesError long before it exhausts them.
  defp submap_gen(keys, value_gen) do
    absent = make_ref()

    gen all(drawn <- fixed_map(Map.new(keys, &{&1, one_of([value_gen, constant(absent)])}))) do
      for {key, value} <- drawn, value != absent, into: %{}, do: {key, value}
    end
  end

  # Deliberately disjoint from the allowlists, so a generated "dropped" key is never one the
  # filter is supposed to keep.
  defp name_gen, do: map(string(?a..?z, min_length: 1, max_length: 6), &("field_" <> &1))

  defp pii_value_gen, do: map(string(?a..?z, min_length: 1, max_length: 8), &(@pii_prefix <> &1))

  defp safe_value_gen, do: map(string(?a..?z, min_length: 1, max_length: 8), &("ok-" <> &1))

  defp allowed_args, do: ~w(invite_id user_id program_id child_id trace_context)

  defp allowed_params, do: ~w(invite_id user_id child_id consent page _target)
end
