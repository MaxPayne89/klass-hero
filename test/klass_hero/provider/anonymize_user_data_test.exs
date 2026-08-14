defmodule KlassHero.Provider.AnonymizeUserDataTest do
  @moduledoc """
  Tests for the Provider context's slice of the GDPR erasure cascade.
  """
  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures
  import KlassHero.EventTestHelper
  import KlassHero.Factory
  import KlassHero.ProviderFixtures

  alias KlassHero.Provider
  alias KlassHero.Provider.IncidentReport
  alias KlassHero.Provider.ProgramStaffAssignment
  alias KlassHero.Provider.StaffMember

  setup do
    setup_test_integration_events()
  end

  describe "anonymize_data_for_user/1" do
    test "scrubs both PII surfaces and reports what it touched" do
      %{user: user, report: report, staff: staff} = user_with_provider_data()

      assert {:ok, %{incident_reports: 1, staff_members: 1}} = Provider.anonymize_data_for_user(user.id)

      assert Repo.get(IncidentReport, report.id).reporter_display_name ==
               IncidentReport.anonymized_attrs().reporter_display_name

      reloaded_staff = Repo.get(StaffMember, staff.id)
      assert StaffMember.full_name(reloaded_staff) == "Deleted User"
      assert reloaded_staff.email == nil
      refute reloaded_staff.active
    end

    test "returns :no_data when the user owns nothing in this context" do
      user = unconfirmed_user_fixture(intended_roles: [:parent])

      assert {:ok, :no_data} = Provider.anonymize_data_for_user(user.id)
    end

    test "is idempotent" do
      %{user: user} = user_with_provider_data()

      assert {:ok, first} = Provider.anonymize_data_for_user(user.id)
      assert {:ok, second} = Provider.anonymize_data_for_user(user.id)

      assert first == second
    end

    test "leaves another user's data untouched" do
      %{user: user} = user_with_provider_data()
      %{report: other_report, staff: other_staff} = user_with_provider_data()

      assert {:ok, _} = Provider.anonymize_data_for_user(user.id)

      assert Repo.get(IncidentReport, other_report.id).reporter_display_name == "Jane Whistleblower"
      assert Repo.get(StaffMember, other_staff.id).active
    end

    test "scrubs a staff row that was already inactive" do
      %{user: user, staff: staff} = user_with_provider_data(active: false)

      assert {:ok, %{staff_members: 1}} = Provider.anonymize_data_for_user(user.id)

      assert Repo.get(StaffMember, staff.id).email == nil
    end

    test "ends the employment link with its consequences, not just the PII" do
      # Erasure goes through offboard_staff_member/1 rather than flipping `active`
      # itself, so it inherits every consequence instead of having to remember them:
      # the lead-instructor flag goes, and the event that clears the erased name from
      # read tables is staged (#1237).
      %{user: user, provider: provider, program: program, staff: staff} = user_with_provider_data()

      {:ok, lead} = Provider.set_lead_instructor(program.id, staff.id, provider.id)
      assert lead.is_lead_instructor

      clear_integration_events()

      assert {:ok, _} = Provider.anonymize_data_for_user(user.id)

      refute Repo.get(ProgramStaffAssignment, lead.id).is_lead_instructor
      assert_integration_event_published(:staff_member_deactivated, %{staff_member_id: staff.id})
    end

    test "takes the erased person out of their programs' conversations" do
      # An erased user who stays an active conversation participant is the #1292
      # defect wearing a different trigger: the name renders as "Deleted User", but
      # the account is still in the thread. Erasure offboards rather than
      # deactivates, so each assignment is retired through the event path Messaging
      # listens to.
      %{user: user, provider: provider, program: program, staff: staff} = user_with_provider_data()

      {:ok, assignment} =
        Provider.assign_staff_to_program(%{
          provider_id: provider.id,
          program_id: program.id,
          staff_member_id: staff.id
        })

      clear_integration_events()

      assert {:ok, _} = Provider.anonymize_data_for_user(user.id)

      assert %DateTime{} = Repo.get(ProgramStaffAssignment, assignment.id).unassigned_at

      assert_integration_event_published(:staff_unassigned_from_program, %{
        program_id: program.id,
        staff_user_id: user.id
      })
    end
  end

  defp user_with_provider_data(staff_attrs \\ []) do
    user = user_fixture(intended_roles: [:staff, :provider])
    provider = provider_profile_fixture(identity_id: user.id)
    program = insert(:program_schema, provider_id: provider.id)

    staff =
      staff_member_fixture(
        Keyword.merge(
          [
            provider_id: provider.id,
            user_id: user.id,
            first_name: "Jane",
            last_name: "Whistleblower",
            email: "jane@example.com",
            invitation_status: :accepted
          ],
          staff_attrs
        )
      )

    report =
      incident_report_fixture(
        provider_profile_id: provider.id,
        reporter_user_id: user.id,
        reporter_display_name: "Jane Whistleblower",
        program_id: program.id
      )

    %{user: user, provider: provider, program: program, staff: staff, report: report}
  end
end
