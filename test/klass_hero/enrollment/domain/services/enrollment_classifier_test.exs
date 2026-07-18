defmodule KlassHero.Enrollment.Domain.Services.EnrollmentClassifierTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias KlassHero.Enrollment.Domain.Services.EnrollmentClassifier
  alias KlassHero.Enrollment.Enrollment
  alias KlassHero.ProgramCatalog.Program

  @today ~D[2026-03-15]

  defp build_enrollment(overrides \\ []) do
    struct!(
      %Enrollment{
        id: "enroll-#{System.unique_integer([:positive])}",
        program_id: "prog-1",
        child_id: "child-1",
        parent_id: "parent-1",
        status: :confirmed,
        enrolled_at: ~U[2026-01-01 00:00:00Z]
      },
      overrides
    )
  end

  defp build_program(overrides) do
    struct!(
      %Program{
        id: "prog-#{System.unique_integer([:positive])}",
        provider_id: "prov-1",
        title: "Test Program",
        description: "A test",
        category: "sports",
        price: Decimal.new("25.00"),
        pricing_period: "session",
        meeting_days: [],
        start_date: ~D[2026-03-01],
        end_date: ~D[2026-06-30]
      },
      overrides
    )
  end

  defp enrollment_program_generator do
    gen all(
          status <- member_of([:confirmed, :pending, :completed, :cancelled]),
          end_date <- one_of([constant(nil), map(integer(-30..30), &Date.add(@today, &1))]),
          start_date <- one_of([constant(nil), map(integer(-30..30), &Date.add(@today, &1))])
        ) do
      {build_enrollment(status: status), build_program(end_date: end_date, start_date: start_date)}
    end
  end

  # Ascending/descending check that tolerates nils, as long as they're
  # clustered at the end — avoids reimplementing Enum.sort_by/2 in the test.
  defp sorted_nils_last?(dates, in_order?) do
    dates
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn
      [nil, next] -> is_nil(next)
      [_prev, nil] -> true
      [prev, next] -> in_order?.(prev, next)
    end)
  end

  describe "classify/2 - empty input" do
    test "returns empty tuple for empty list" do
      assert {[], []} = EnrollmentClassifier.classify([], @today)
    end
  end

  # Every row exercises the same contract: a single enrollment+program pair
  # is either active or expired based on status and end_date relative to @today.
  @classification_cases [
    {:confirmed, ~D[2026-06-30], :active, "confirmed + future end_date"},
    {:pending, ~D[2026-06-30], :active, "pending + future end_date"},
    {:completed, ~D[2027-12-31], :expired, "completed overrides future end_date"},
    {:cancelled, ~D[2027-12-31], :expired, "cancelled overrides future end_date"},
    {:confirmed, ~D[2026-01-01], :expired, "confirmed + past end_date"},
    {:confirmed, nil, :active, "confirmed + nil end_date"},
    {:confirmed, @today, :active, "end_date == today is not expired (boundary)"}
  ]

  describe "classify/2 - status/end_date truth table" do
    test "each combination classifies as active or expired" do
      for {status, end_date, expected, label} <- @classification_cases do
        pair = {build_enrollment(status: status), build_program(end_date: end_date)}
        {active, _expired} = EnrollmentClassifier.classify([pair], @today)

        actual = if active == [pair], do: :active, else: :expired
        assert actual == expected, label
      end
    end
  end

  describe "classify/2 - sort order examples" do
    test "active programs sorted by start_date ascending" do
      early = {build_enrollment(), build_program(start_date: ~D[2026-04-01])}
      late = {build_enrollment(), build_program(start_date: ~D[2026-08-01])}
      mid = {build_enrollment(), build_program(start_date: ~D[2026-06-01])}

      {active, _expired} = EnrollmentClassifier.classify([late, early, mid], @today)

      dates = Enum.map(active, fn {_e, p} -> p.start_date end)
      assert dates == [~D[2026-04-01], ~D[2026-06-01], ~D[2026-08-01]]
    end

    test "nil start_date sorted to end of active list" do
      with_date = {build_enrollment(), build_program(start_date: ~D[2026-04-01])}
      no_date = {build_enrollment(), build_program(start_date: nil, end_date: nil)}

      {active, _expired} = EnrollmentClassifier.classify([no_date, with_date], @today)

      dates = Enum.map(active, fn {_e, p} -> p.start_date end)
      assert dates == [~D[2026-04-01], nil]
    end

    test "expired programs sorted by end_date descending" do
      old = {build_enrollment(status: :completed), build_program(end_date: ~D[2025-01-01])}
      recent = {build_enrollment(status: :completed), build_program(end_date: ~D[2026-02-01])}
      mid = {build_enrollment(status: :completed), build_program(end_date: ~D[2025-06-01])}

      {_active, expired} = EnrollmentClassifier.classify([old, recent, mid], @today)

      dates = Enum.map(expired, fn {_e, p} -> p.end_date end)
      assert dates == [~D[2026-02-01], ~D[2025-06-01], ~D[2025-01-01]]
    end
  end

  describe "classify/2 - properties" do
    property "partitions every pair exactly once, sorting active ascending and expired descending, nils last" do
      check all(pairs <- list_of(enrollment_program_generator(), max_length: 20)) do
        {active, expired} = EnrollmentClassifier.classify(pairs, @today)

        # partition completeness: every input pair lands in exactly one bucket
        assert length(active) + length(expired) == length(pairs)

        input_ids = MapSet.new(pairs, fn {e, _p} -> e.id end)
        output_ids = MapSet.new(active ++ expired, fn {e, _p} -> e.id end)
        assert output_ids == input_ids

        # sort-order invariants
        active_dates = Enum.map(active, fn {_e, p} -> p.start_date end)
        assert sorted_nils_last?(active_dates, &(not Date.after?(&1, &2)))

        expired_dates = Enum.map(expired, fn {_e, p} -> p.end_date end)
        assert sorted_nils_last?(expired_dates, &(not Date.before?(&1, &2)))
      end
    end
  end
end
