defmodule KlassHero.Provider.Verification.VerificationDocumentTest do
  @moduledoc """
  Tests for the VerificationDocument functional core — the pure expiry helpers that
  classify a policy expiry date and declare which document types require one (vetting
  step B3, #957). In-memory; no database.
  """

  use ExUnit.Case, async: true

  alias KlassHero.Provider.VerificationDocument

  @today ~D[2026-07-13]

  describe "expiry_status/2" do
    # {expiry_date, expected} against a fixed @today. Boundary intent (D4):
    # :expired only when strictly BEFORE today; expiring today is still :expiring_soon
    # (diff 0); exactly 30 days out is the last :expiring_soon day; 31 is :valid.
    @cases [
      {nil, :none},
      {~D[2026-07-12], :expired},
      {~D[2026-07-13], :expiring_soon},
      {~D[2026-07-14], :expiring_soon},
      {~D[2026-08-12], :expiring_soon},
      {~D[2026-08-13], :valid},
      {~D[2027-07-13], :valid}
    ]

    test "classifies a date relative to today" do
      for {date, expected} <- @cases do
        assert VerificationDocument.expiry_status(date, @today) == expected,
               "expected #{inspect(date)} -> #{expected} (today #{@today})"
      end
    end

    test "accepts a VerificationDocument struct, reading its expiry_date" do
      assert VerificationDocument.expiry_status(%VerificationDocument{expiry_date: ~D[2026-07-01]}, @today) ==
               :expired

      assert VerificationDocument.expiry_status(%VerificationDocument{expiry_date: nil}, @today) == :none
    end
  end

  describe "expiry_required?/1" do
    test "true only for insurance_certificate" do
      assert VerificationDocument.expiry_required?("insurance_certificate")
      refute VerificationDocument.expiry_required?("background_check")
      refute VerificationDocument.expiry_required?("business_registration")
      refute VerificationDocument.expiry_required?("safeguarding_certificate")
    end
  end
end
