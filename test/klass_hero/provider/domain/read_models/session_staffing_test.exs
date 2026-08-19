defmodule KlassHero.Provider.Domain.ReadModels.SessionStaffingTest do
  use ExUnit.Case, async: true

  alias KlassHero.Provider.Domain.ReadModels.SessionStaffing

  defp staffing(overrides \\ %{}) do
    struct!(
      %SessionStaffing{
        session_id: "sess-1",
        program_id: "prog-1",
        lead: nil,
        member_ids: [],
        member_count: 0,
        source: :program
      },
      overrides
    )
  end

  describe "empty/2" do
    test "is the zero-staff value and reads as inherited from the program" do
      empty = SessionStaffing.empty("sess-1", "prog-1")

      assert empty.session_id == "sess-1"
      assert empty.program_id == "prog-1"
      assert empty.member_ids == []
      assert empty.member_count == 0
      assert empty.lead == nil
      # A session nobody staffs is inheriting an empty program roster, not
      # overriding it — an override is a row a provider deliberately created.
      assert empty.source == :program
    end
  end

  describe "staffed_by?/2" do
    test "is true for a member, lead or not" do
      s = staffing(%{member_ids: ["staff-1", "staff-2"], member_count: 2, lead: %{id: "staff-1"}})

      assert SessionStaffing.staffed_by?(s, "staff-1")
      assert SessionStaffing.staffed_by?(s, "staff-2")
    end

    test "is false for a non-member" do
      refute SessionStaffing.staffed_by?(staffing(), "staff-9")
    end

    test "accepts nil so a batch-read miss passes straight through" do
      refute SessionStaffing.staffed_by?(nil, "staff-1")
    end
  end

  describe "led_by?/2" do
    test "is true only for the lead" do
      s = staffing(%{member_ids: ["staff-1", "staff-2"], member_count: 2, lead: %{id: "staff-1"}})

      assert SessionStaffing.led_by?(s, "staff-1")
      refute SessionStaffing.led_by?(s, "staff-2")
    end

    test "is false when the session has no lead" do
      refute SessionStaffing.led_by?(staffing(%{member_ids: ["staff-1"], member_count: 1}), "staff-1")
    end

    test "accepts nil" do
      refute SessionStaffing.led_by?(nil, "staff-1")
    end
  end

  describe "overridden?/1" do
    test "distinguishes a deliberate override from an inherited roster" do
      assert SessionStaffing.overridden?(staffing(%{source: :override}))
      refute SessionStaffing.overridden?(staffing(%{source: :program}))
    end
  end
end
