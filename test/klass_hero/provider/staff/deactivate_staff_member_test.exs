defmodule KlassHero.Provider.Staff.DeactivateStaffMemberTest do
  @moduledoc """
  `deactivate_staff_member/1` — the single definition of ending a Staff Member's
  employment link (#1237).

  Before this command existed, `active` was flipped by a bare cast from four
  places and every consequence had to be remembered at each call site. The
  consequences are now: the lead-instructor flag is cleared, an outstanding
  invitation is revoked, and a `staff_member_deactivated` event is staged so
  read tables holding a denormalised staff name can clear it.

  Program Staff Assignments deliberately **survive** — deactivation ends the
  employment, it does not rewrite the roster history, and unassignment would
  strip conversation membership that reactivation cannot give back.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.EventTestHelper
  import KlassHero.Factory

  alias KlassHero.Provider
  alias KlassHero.Provider.ProgramStaffAssignment
  alias KlassHero.Provider.StaffMember
  alias KlassHero.Repo

  setup do
    setup_test_integration_events()

    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)
    staff = insert(:staff_member_schema, provider_id: provider.id)

    clear_integration_events()

    %{provider: provider, program: program, staff: staff}
  end

  defp lead_assignment(program, staff) do
    {:ok, lead} = Provider.set_lead_instructor(program.id, staff.id, program.provider_id)
    lead
  end

  defp reload(%StaffMember{id: id}), do: Repo.get!(StaffMember, id)
  defp reload(%ProgramStaffAssignment{id: id}), do: Repo.get!(ProgramStaffAssignment, id)

  describe "deactivate_staff_member/1" do
    test "ends the employment link", %{staff: staff} do
      assert {:ok, deactivated} = Provider.deactivate_staff_member(staff)

      assert deactivated.active == false
      assert reload(staff).active == false
    end

    test "clears the lead-instructor flag the staff member held", %{program: program, staff: staff} do
      lead = lead_assignment(program, staff)
      assert lead.is_lead_instructor

      {:ok, _} = Provider.deactivate_staff_member(staff)

      refute reload(lead).is_lead_instructor
    end

    test "leaves the assignment itself active", %{program: program, staff: staff} do
      lead = lead_assignment(program, staff)

      {:ok, _} = Provider.deactivate_staff_member(staff)

      assert is_nil(reload(lead).unassigned_at),
             "deactivation must not unassign — that would strip conversation membership"
    end

    test "does not touch another staff member's lead flag", %{provider: provider, program: program, staff: staff} do
      other_program = insert(:program_schema, provider_id: provider.id)
      other_staff = insert(:staff_member_schema, provider_id: provider.id)

      lead = lead_assignment(program, staff)
      other_lead = lead_assignment(other_program, other_staff)

      {:ok, _} = Provider.deactivate_staff_member(staff)

      refute reload(lead).is_lead_instructor
      assert reload(other_lead).is_lead_instructor
      assert reload(other_staff).active
    end

    test "revokes an outstanding invitation", %{provider: provider} do
      invited =
        insert(:staff_member_schema,
          provider_id: provider.id,
          invitation_status: :sent,
          invitation_token_hash: :crypto.hash(:sha256, "token"),
          invitation_sent_at: DateTime.utc_now()
        )

      {:ok, _} = Provider.deactivate_staff_member(invited)

      revoked = reload(invited)
      assert is_nil(revoked.invitation_token_hash)
      assert revoked.invitation_status == :expired
    end

    test "leaves an accepted invitation intact", %{provider: provider} do
      accepted = insert(:staff_member_schema, provider_id: provider.id, invitation_status: :accepted)

      {:ok, _} = Provider.deactivate_staff_member(accepted)

      assert reload(accepted).invitation_status == :accepted
    end

    test "stages a staff_member_deactivated event on the provider topic", %{provider: provider, staff: staff} do
      {:ok, _} = Provider.deactivate_staff_member(staff)

      event =
        assert_integration_published_to(
          :staff_member_deactivated,
          "integration:provider:staff_member_deactivated"
        )

      assert event.payload.staff_member_id == staff.id
      assert event.payload.provider_id == provider.id
    end

    test "is idempotent and stages nothing for an already-inactive member", %{provider: provider} do
      inactive = insert(:staff_member_schema, provider_id: provider.id, active: false)

      assert {:ok, unchanged} = Provider.deactivate_staff_member(inactive)

      assert unchanged.active == false
      assert_no_integration_events_published()
    end
  end

  describe "reactivate_staff_member/1" do
    test "restores the employment link", %{staff: staff} do
      {:ok, deactivated} = Provider.deactivate_staff_member(staff)

      assert {:ok, reactivated} = Provider.reactivate_staff_member(deactivated)

      assert reactivated.active
      assert reload(staff).active
    end

    test "does not restore the lead-instructor flag", %{program: program, staff: staff} do
      lead = lead_assignment(program, staff)
      {:ok, deactivated} = Provider.deactivate_staff_member(staff)

      {:ok, _} = Provider.reactivate_staff_member(deactivated)

      refute reload(lead).is_lead_instructor,
             "lead is a deliberate promotion — reinstating employment must not re-confer it"
    end
  end
end
