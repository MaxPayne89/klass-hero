defmodule KlassHeroWeb.Helpers.ParticipationEditHelpersTest do
  use ExUnit.Case, async: true

  alias KlassHero.Participation.Domain.Models.ParticipationRecord
  alias KlassHeroWeb.Helpers.ParticipationEditHelpers

  @base_attrs %{id: "rec-001", session_id: "ses-001", child_id: "chi-001", status: :checked_in}

  defp build_record(overrides \\ []) do
    struct!(ParticipationRecord, Map.merge(@base_attrs, Map.new(overrides)))
  end

  describe "default_edit_notes/1" do
    test "returns check_out_notes when child has departed with notes" do
      record = build_record(check_out_at: ~U[2026-01-01 15:00:00Z], check_out_notes: "Left early")
      assert ParticipationEditHelpers.default_edit_notes(record) == "Left early"
    end

    test "returns empty string when child has departed but check_out_notes is nil" do
      record = build_record(check_out_at: ~U[2026-01-01 15:00:00Z], check_out_notes: nil)
      assert ParticipationEditHelpers.default_edit_notes(record) == ""
    end

    test "returns check_in_notes when child has not yet departed" do
      record = build_record(check_in_notes: "Arrived late")
      assert ParticipationEditHelpers.default_edit_notes(record) == "Arrived late"
    end

    test "returns empty string when no departure and check_in_notes is nil" do
      record = build_record(check_in_notes: nil)
      assert ParticipationEditHelpers.default_edit_notes(record) == ""
    end

    test "returns empty string for an unrecognized shape (fallback clause)" do
      assert ParticipationEditHelpers.default_edit_notes(%{}) == ""
    end
  end

  describe "build_edit_correction/3" do
    test "records a retroactive check-out when departure time is supplied and child has not yet departed" do
      record = build_record()
      params = %{"check_out_at" => "2026-01-01T15:00", "notes" => "Early pickup"}

      assert {:ok, cmd} = ParticipationEditHelpers.build_edit_correction(record, params, :provider)

      assert cmd.status == :checked_out
      assert cmd.check_out_at == ~U[2026-01-01 15:00:00Z]
      assert cmd.check_out_notes == "Early pickup"
      assert cmd.actor_role == :provider
      assert cmd.record_id == "rec-001"
    end

    test "returns error when departure time string is invalid" do
      record = build_record()
      params = %{"check_out_at" => "not-a-date", "notes" => ""}

      assert {:error, :invalid_datetime} =
               ParticipationEditHelpers.build_edit_correction(record, params, :staff)
    end

    test "updates check_out_notes when child has already departed" do
      record = build_record(check_out_at: ~U[2026-01-01 15:00:00Z])
      params = %{"notes" => "Updated note", "check_out_at" => ""}

      assert {:ok, cmd} = ParticipationEditHelpers.build_edit_correction(record, params, :staff)

      assert cmd.check_out_notes == "Updated note"
      assert cmd.actor_role == :staff
      refute Map.has_key?(cmd, :status)
    end

    test "updates check_in_notes when no departure time is given and child has not departed" do
      record = build_record()
      params = %{"notes" => "Late arrival", "check_out_at" => ""}

      assert {:ok, cmd} = ParticipationEditHelpers.build_edit_correction(record, params, :provider)

      assert cmd.check_in_notes == "Late arrival"
      assert cmd.actor_role == :provider
      refute Map.has_key?(cmd, :check_out_notes)
    end

    test "defaults to empty string when notes key is absent from params" do
      record = build_record()
      params = %{}

      assert {:ok, cmd} = ParticipationEditHelpers.build_edit_correction(record, params, :provider)
      assert cmd.check_in_notes == ""
    end

    test "parses departure time that already includes seconds" do
      record = build_record()
      params = %{"check_out_at" => "2026-01-01T15:00:30", "notes" => ""}

      assert {:ok, cmd} = ParticipationEditHelpers.build_edit_correction(record, params, :provider)
      assert cmd.check_out_at == ~U[2026-01-01 15:00:30Z]
    end

    test "ignores supplied departure time when child is already checked out (departed child takes branch 2)" do
      record = build_record(check_out_at: ~U[2026-01-01 15:00:00Z])
      params = %{"check_out_at" => "2026-01-01T16:00", "notes" => "Override attempt"}

      assert {:ok, cmd} = ParticipationEditHelpers.build_edit_correction(record, params, :staff)

      # Branch 2 wins: record already has check_out_at, so only notes are updated
      assert cmd.check_out_notes == "Override attempt"
      refute Map.has_key?(cmd, :check_out_at)
    end
  end
end
