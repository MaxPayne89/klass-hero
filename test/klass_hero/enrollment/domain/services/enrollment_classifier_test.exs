defmodule KlassHero.Enrollment.Domain.Services.EnrollmentClassifierTest do
  use ExUnit.Case, async: true

  alias KlassHero.Enrollment.Domain.Models.Enrollment
  alias KlassHero.Enrollment.Domain.Services.EnrollmentClassifier
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

  describe "classify/2" do
    test "returns empty tuple for empty list" do
      assert {[], []} = EnrollmentClassifier.classify([], @today)
    end

    test "confirmed enrollment with future end_date is active" do
      pair = {build_enrollment(status: :confirmed), build_program(end_date: ~D[2026-06-30])}

      {active, expired} = EnrollmentClassifier.classify([pair], @today)

      assert length(active) == 1
      assert expired == []
    end

    test "pending enrollment with future end_date is active" do
      pair = {build_enrollment(status: :pending), build_program(end_date: ~D[2026-06-30])}

      {active, expired} = EnrollmentClassifier.classify([pair], @today)

      assert length(active) == 1
      assert expired == []
    end

    test "completed enrollment is expired regardless of end_date" do
      pair = {build_enrollment(status: :completed), build_program(end_date: ~D[2027-12-31])}

      {active, expired} = EnrollmentClassifier.classify([pair], @today)

      assert active == []
      assert length(expired) == 1
    end

    test "cancelled enrollment is expired regardless of end_date" do
      pair = {build_enrollment(status: :cancelled), build_program(end_date: ~D[2027-12-31])}

      {active, expired} = EnrollmentClassifier.classify([pair], @today)

      assert active == []
      assert length(expired) == 1
    end

    test "confirmed enrollment with past end_date is expired" do
      pair = {build_enrollment(status: :confirmed), build_program(end_date: ~D[2026-01-01])}

      {active, expired} = EnrollmentClassifier.classify([pair], @today)

      assert active == []
      assert length(expired) == 1
    end

    test "enrollment with nil end_date is active" do
      pair = {build_enrollment(status: :confirmed), build_program(end_date: nil)}

      {active, expired} = EnrollmentClassifier.classify([pair], @today)

      assert length(active) == 1
      assert expired == []
    end

    test "end_date equal to today is not expired" do
      pair = {build_enrollment(status: :confirmed), build_program(end_date: @today)}

      {active, expired} = EnrollmentClassifier.classify([pair], @today)

      assert length(active) == 1
      assert expired == []
    end

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
end
