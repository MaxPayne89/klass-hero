defmodule KlassHeroWeb.Helpers.ParticipationEditHelpersTest do
  use ExUnit.Case, async: true

  alias KlassHero.Participation.ParticipationRecord
  alias KlassHeroWeb.Helpers.ParticipationEditHelpers

  @base_attrs %{id: "rec-001", session_id: "ses-001", child_id: "chi-001", status: :checked_in}
  @departed ~U[2026-01-01 15:00:00Z]

  defp build_record(overrides \\ []) do
    struct!(ParticipationRecord, Map.merge(@base_attrs, Map.new(overrides)))
  end

  describe "default_edit_notes/1" do
    # One row per function clause: {record overrides, expected text, label}.
    @notes_cases [
      {[check_out_at: @departed, check_out_notes: "Left early"], "Left early", "departed with check_out_notes"},
      {[check_out_at: @departed, check_out_notes: nil], "",
       "departed but no check_out_notes (empty, not copied from check-in)"},
      {[check_in_notes: "Arrived late"], "Arrived late", "not departed, has check_in_notes"},
      {[check_in_notes: nil], "", "not departed, no check_in_notes"}
    ]

    test "falls back to the notes field the edit will write to" do
      for {overrides, expected, label} <- @notes_cases do
        actual = ParticipationEditHelpers.default_edit_notes(build_record(overrides))
        assert actual == expected, "#{label}: expected #{inspect(expected)}, got #{inspect(actual)}"
      end
    end

    test "returns empty string for an unrecognised shape (fallback clause)" do
      assert ParticipationEditHelpers.default_edit_notes(%{}) == ""
    end
  end

  describe "build_edit_correction/3" do
    # The three cond branches, each asserted for BOTH actor roles — role is
    # incidental data threaded through unchanged, so iterating proves passthrough
    # without duplicating the branch logic per role.
    for role <- [:provider, :staff] do
      test "records a retroactive check-out when a departure time is supplied (#{role})" do
        record = build_record()
        params = %{"check_out_at" => "2026-01-01T15:00", "notes" => "Early pickup"}

        assert {:ok, cmd} = ParticipationEditHelpers.build_edit_correction(record, params, unquote(role))

        assert cmd.status == :checked_out
        assert cmd.check_out_at == ~U[2026-01-01 15:00:00Z]
        assert cmd.check_out_notes == "Early pickup"
        assert cmd.record_id == "rec-001"
        assert cmd.actor_role == unquote(role)
      end

      test "writes check_out_notes when the child has already departed (#{role})" do
        record = build_record(check_out_at: @departed)
        params = %{"notes" => "Updated note", "check_out_at" => ""}

        assert {:ok, cmd} = ParticipationEditHelpers.build_edit_correction(record, params, unquote(role))

        assert cmd.check_out_notes == "Updated note"
        assert cmd.actor_role == unquote(role)
        refute Map.has_key?(cmd, :status)
      end

      test "writes check_in_notes when no departure time and child not departed (#{role})" do
        record = build_record()
        params = %{"notes" => "Late arrival", "check_out_at" => ""}

        assert {:ok, cmd} = ParticipationEditHelpers.build_edit_correction(record, params, unquote(role))

        assert cmd.check_in_notes == "Late arrival"
        assert cmd.actor_role == unquote(role)
        refute Map.has_key?(cmd, :check_out_notes)
      end
    end

    test "returns error when the departure time string is invalid" do
      record = build_record()
      params = %{"check_out_at" => "not-a-date", "notes" => ""}

      assert {:error, :invalid_datetime} =
               ParticipationEditHelpers.build_edit_correction(record, params, :staff)
    end

    test "defaults notes to empty string when the notes key is absent" do
      record = build_record()

      assert {:ok, cmd} = ParticipationEditHelpers.build_edit_correction(record, %{}, :provider)
      assert cmd.check_in_notes == ""
    end

    test "an already-departed child ignores a supplied departure time (branch 2 wins)" do
      record = build_record(check_out_at: @departed)
      params = %{"check_out_at" => "2026-01-01T16:00", "notes" => "Override attempt"}

      assert {:ok, cmd} = ParticipationEditHelpers.build_edit_correction(record, params, :staff)

      assert cmd.check_out_notes == "Override attempt"
      refute Map.has_key?(cmd, :check_out_at)
    end

    # parse_datetime_local normalises 16-char "datetime-local" input by appending
    # ":00"; 19-char input already has seconds. These are the two sides of the
    # byte_size(input) == 16 boundary.
    test "parses datetime-local input at the seconds boundary (16 chars, no seconds)" do
      record = build_record()
      params = %{"check_out_at" => "2026-01-01T15:00", "notes" => ""}

      assert {:ok, cmd} = ParticipationEditHelpers.build_edit_correction(record, params, :provider)
      assert cmd.check_out_at == ~U[2026-01-01 15:00:00Z]
    end

    test "parses datetime-local input past the boundary (19 chars, with seconds)" do
      record = build_record()
      params = %{"check_out_at" => "2026-01-01T15:00:30", "notes" => ""}

      assert {:ok, cmd} = ParticipationEditHelpers.build_edit_correction(record, params, :provider)
      assert cmd.check_out_at == ~U[2026-01-01 15:00:30Z]
    end
  end
end
