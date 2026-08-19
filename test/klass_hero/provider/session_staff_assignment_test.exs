defmodule KlassHero.Provider.SessionStaffAssignmentTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Provider.SessionStaffAssignment
  alias KlassHero.Repo

  defp session_context do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)
    session = insert(:program_session_schema, program_id: program.id)
    staff = insert(:staff_member_schema, provider_id: provider.id)

    %{provider: provider, session: session, staff: staff}
  end

  defp create_attrs(%{provider: provider, session: session, staff: staff}, overrides \\ %{}) do
    Map.merge(
      %{
        provider_id: provider.id,
        session_id: session.id,
        staff_member_id: staff.id,
        assigned_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
      },
      overrides
    )
  end

  describe "create_changeset/2" do
    test "requires provider_id, session_id, staff_member_id and assigned_at" do
      changeset = SessionStaffAssignment.create_changeset(%SessionStaffAssignment{}, %{})

      refute changeset.valid?

      assert %{
               provider_id: ["can't be blank"],
               session_id: ["can't be blank"],
               staff_member_id: ["can't be blank"],
               assigned_at: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "sets provider_id and staff_member_id via put_change, not cast" do
      # Trigger: these are programmatic keys — the command takes them from the
      #          ownership-proven StaffMember, never from caller-supplied attrs.
      changeset =
        SessionStaffAssignment.create_changeset(%SessionStaffAssignment{}, %{
          provider_id: "p-1",
          staff_member_id: "s-1",
          session_id: "sess-1",
          assigned_at: DateTime.utc_now()
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :provider_id) == "p-1"
      assert Ecto.Changeset.get_field(changeset, :staff_member_id) == "s-1"
    end

    test "rejects a second active assignment of the same staff member to the same session" do
      ctx = session_context()

      assert {:ok, _first} =
               %SessionStaffAssignment{}
               |> SessionStaffAssignment.create_changeset(create_attrs(ctx))
               |> Repo.insert()

      assert {:error, changeset} =
               %SessionStaffAssignment{}
               |> SessionStaffAssignment.create_changeset(create_attrs(ctx))
               |> Repo.insert()

      assert %{session_id: ["staff member is already assigned to this session"]} = errors_on(changeset)
    end
  end

  describe "active?/1" do
    test "is true when never unassigned" do
      assert SessionStaffAssignment.active?(%SessionStaffAssignment{unassigned_at: nil})
    end

    test "is false once unassigned" do
      refute SessionStaffAssignment.active?(%SessionStaffAssignment{unassigned_at: DateTime.utc_now()})
    end
  end

  describe "lead?/1" do
    test "is true only for an active, flagged assignment" do
      assert SessionStaffAssignment.lead?(%SessionStaffAssignment{is_lead_instructor: true, unassigned_at: nil})
    end

    test "is false for a retired assignment even when the flag survived" do
      refute SessionStaffAssignment.lead?(%SessionStaffAssignment{
               is_lead_instructor: true,
               unassigned_at: DateTime.utc_now()
             })
    end

    test "is false for an active assignment that does not lead" do
      refute SessionStaffAssignment.lead?(%SessionStaffAssignment{is_lead_instructor: false, unassigned_at: nil})
    end
  end

  describe "unassign_changeset/1" do
    test "clears the lead flag so a retired row can never read as both dead and leading" do
      changeset = SessionStaffAssignment.unassign_changeset(%SessionStaffAssignment{is_lead_instructor: true})

      assert %DateTime{} = Ecto.Changeset.get_field(changeset, :unassigned_at)
      refute Ecto.Changeset.get_field(changeset, :is_lead_instructor)
    end

    test "lifts the partial unique index so the same staff member can be re-assigned" do
      ctx = session_context()

      {:ok, first} =
        %SessionStaffAssignment{}
        |> SessionStaffAssignment.create_changeset(create_attrs(ctx))
        |> Repo.insert()

      {:ok, _retired} = first |> SessionStaffAssignment.unassign_changeset() |> Repo.update()

      assert {:ok, _second} =
               %SessionStaffAssignment{}
               |> SessionStaffAssignment.create_changeset(create_attrs(ctx))
               |> Repo.insert()
    end
  end

  describe "lead_changeset/2" do
    test "surfaces a second lead on the same session as a changeset error, not a raw DB exception" do
      ctx = session_context()
      other_staff = insert(:staff_member_schema, provider_id: ctx.provider.id)

      {:ok, _lead} =
        %SessionStaffAssignment{}
        |> SessionStaffAssignment.create_changeset(create_attrs(ctx, %{is_lead_instructor: true}))
        |> Repo.insert()

      {:ok, second} =
        %SessionStaffAssignment{}
        |> SessionStaffAssignment.create_changeset(create_attrs(ctx, %{staff_member_id: other_staff.id}))
        |> Repo.insert()

      assert {:error, changeset} = second |> SessionStaffAssignment.lead_changeset(true) |> Repo.update()
      assert %{session_id: ["session already has a lead instructor"]} = errors_on(changeset)
    end
  end

  describe "owned_by/2" do
    test "narrows to the given provider's rows" do
      ctx = session_context()
      other_provider = insert(:provider_profile_schema)

      {:ok, mine} =
        %SessionStaffAssignment{}
        |> SessionStaffAssignment.create_changeset(create_attrs(ctx))
        |> Repo.insert()

      assert [found] = SessionStaffAssignment.owned_by(ctx.provider.id) |> Repo.all()
      assert found.id == mine.id

      assert [] = SessionStaffAssignment.owned_by(other_provider.id) |> Repo.all()
    end
  end
end
