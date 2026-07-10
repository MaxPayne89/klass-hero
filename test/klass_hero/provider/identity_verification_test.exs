defmodule KlassHero.Provider.IdentityVerificationTest do
  @moduledoc """
  Tests for the IdentityVerification functional core — the evidence for a Stripe Identity
  vetting step. Covers the pure, fail-closed 18+ age gate (ADR-0009). In-memory only.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias KlassHero.Provider.IdentityVerification

  describe "age_18_plus?/2" do
    test "an adult well over 18 passes" do
      assert IdentityVerification.age_18_plus?(%{day: 1, month: 1, year: 1990}, ~D[2026-06-18])
    end

    test "exactly 18 today passes (>= boundary)" do
      assert IdentityVerification.age_18_plus?(%{day: 18, month: 6, year: 2008}, ~D[2026-06-18])
    end

    test "one day before the 18th birthday fails" do
      refute IdentityVerification.age_18_plus?(%{day: 19, month: 6, year: 2008}, ~D[2026-06-18])
    end

    test "a clear minor fails" do
      refute IdentityVerification.age_18_plus?(%{day: 1, month: 1, year: 2015}, ~D[2026-06-18])
    end

    test "a Feb-29 birthday turning 18 in a non-leap year passes on Mar 1" do
      # Born 2008-02-29; 2026 is not a leap year. The 18th birthday normalises to 2026-03-01.
      refute IdentityVerification.age_18_plus?(%{day: 29, month: 2, year: 2008}, ~D[2026-02-28])
      assert IdentityVerification.age_18_plus?(%{day: 29, month: 2, year: 2008}, ~D[2026-03-01])
    end

    test "nil DOB fails closed" do
      refute IdentityVerification.age_18_plus?(nil, ~D[2026-06-18])
    end

    test "a malformed / incomplete DOB fails closed" do
      refute IdentityVerification.age_18_plus?(%{day: 0, month: 0, year: 0}, ~D[2026-06-18])
      refute IdentityVerification.age_18_plus?(%{day: 1, month: 1}, ~D[2026-06-18])
      refute IdentityVerification.age_18_plus?(%{"day" => 1}, ~D[2026-06-18])
    end

    test "a future birth date fails closed" do
      refute IdentityVerification.age_18_plus?(%{day: 1, month: 1, year: 2030}, ~D[2026-06-18])
    end

    test "non-integer DOB fields fail closed" do
      refute IdentityVerification.age_18_plus?(%{day: "1", month: "1", year: "1990"}, ~D[2026-06-18])
      refute IdentityVerification.age_18_plus?(%{day: 1.0, month: 1.0, year: 1990.0}, ~D[2026-06-18])
    end

    property "matches the 18th-birthday boundary for well-formed dates" do
      check all(
              year <- integer(1960..2010),
              month <- integer(1..12),
              # day 1..28 keeps every (month, year) valid and sidesteps the Feb-29 case
              # (covered by its own example above).
              day <- integer(1..28),
              today <- date_generator()
            ) do
        dob = %{day: day, month: month, year: year}
        {:ok, birthday} = Date.new(year + 18, month, day)
        expected = not Date.before?(today, birthday)
        assert IdentityVerification.age_18_plus?(dob, today) == expected
      end
    end

    property "any input that is not a %{day, month, year} of integers fails closed" do
      bad_input =
        one_of([
          constant(nil),
          string(:printable),
          integer(),
          constant(%{day: 1, month: 1}),
          constant(%{"day" => 1, "month" => 1, "year" => 1990}),
          map_of(string(:alphanumeric), integer())
        ])

      check all(bad <- bad_input) do
        refute IdentityVerification.age_18_plus?(bad, ~D[2026-06-18])
      end
    end
  end

  describe "new/1" do
    test "starts a processing record carrying the provider and Stripe session ids" do
      iv = IdentityVerification.new(%{provider_id: "prov-1", stripe_session_id: "vs_123"})

      assert iv.provider_id == "prov-1"
      assert iv.stripe_session_id == "vs_123"
      assert iv.status == :processing
      assert iv.outcome == nil
      assert iv.failure_reason == nil
      assert is_binary(iv.id)
    end
  end

  describe "mark_verified/3" do
    setup do
      %{iv: IdentityVerification.new(%{provider_id: "prov-1", stripe_session_id: "vs_123"})}
    end

    test "an adult passes: status verified, outcome pass, verified_at stamped", %{iv: iv} do
      result = IdentityVerification.mark_verified(iv, %{day: 1, month: 1, year: 1990}, ~D[2026-06-18])

      assert result.status == :verified
      assert result.outcome == :pass
      assert result.failure_reason == nil
      assert %DateTime{} = result.verified_at
    end

    test "a minor fails closed with under_18", %{iv: iv} do
      result = IdentityVerification.mark_verified(iv, %{day: 1, month: 1, year: 2015}, ~D[2026-06-18])

      assert result.status == :verified
      assert result.outcome == :fail
      assert result.failure_reason == "under_18"
    end

    test "a missing/unparseable DOB fails closed with age_unverifiable", %{iv: iv} do
      result = IdentityVerification.mark_verified(iv, nil, ~D[2026-06-18])

      assert result.status == :verified
      assert result.outcome == :fail
      assert result.failure_reason == "age_unverifiable"
    end
  end

  describe "mark_requires_input/1 and mark_canceled/1" do
    setup do
      %{iv: IdentityVerification.new(%{provider_id: "prov-1", stripe_session_id: "vs_123"})}
    end

    test "requires_input is a failed outcome", %{iv: iv} do
      result = IdentityVerification.mark_requires_input(iv)

      assert result.status == :requires_input
      assert result.outcome == :fail
      assert result.failure_reason == "requires_input"
    end

    test "canceled is a failed outcome", %{iv: iv} do
      result = IdentityVerification.mark_canceled(iv)

      assert result.status == :canceled
      assert result.outcome == :fail
      assert result.failure_reason == "canceled"
    end
  end

  defp date_generator do
    gen all(
          year <- integer(2015..2035),
          month <- integer(1..12),
          day <- integer(1..28)
        ) do
      Date.new!(year, month, day)
    end
  end
end
