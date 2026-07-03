defmodule KlassHero.Provider.ProgramStaffAssignmentTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Provider.ProgramStaffAssignment
  alias KlassHero.Repo

  describe "create_changeset/2" do
    test "requires provider_id, program_id, staff_member_id and assigned_at" do
      changeset = ProgramStaffAssignment.create_changeset(%ProgramStaffAssignment{}, %{})

      refute changeset.valid?

      assert %{
               provider_id: ["can't be blank"],
               program_id: ["can't be blank"],
               staff_member_id: ["can't be blank"],
               assigned_at: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "sets provider_id and staff_member_id via put_change, not cast" do
      # Trigger: these are programmatic keys — a caller passing them as string keys
      #          still lands them, but they are never castable user input.
      changeset =
        ProgramStaffAssignment.create_changeset(%ProgramStaffAssignment{}, %{
          provider_id: "p-1",
          staff_member_id: "s-1",
          program_id: "prog-1",
          assigned_at: DateTime.utc_now()
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :provider_id) == "p-1"
      assert Ecto.Changeset.get_field(changeset, :staff_member_id) == "s-1"
    end
  end

  describe "active?/1" do
    test "is true when never unassigned" do
      assert ProgramStaffAssignment.active?(%ProgramStaffAssignment{unassigned_at: nil})
    end

    test "is false once unassigned" do
      refute ProgramStaffAssignment.active?(%ProgramStaffAssignment{
               unassigned_at: DateTime.utc_now()
             })
    end
  end

  describe "unassign_changeset/1 lifts the partial unique index" do
    test "the same staff member can be re-assigned after being unassigned" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      staff = insert(:staff_member_schema, provider_id: provider.id)

      attrs = %{
        provider_id: provider.id,
        program_id: program.id,
        staff_member_id: staff.id,
        assigned_at: DateTime.utc_now()
      }

      {:ok, first} =
        %ProgramStaffAssignment{}
        |> ProgramStaffAssignment.create_changeset(attrs)
        |> Repo.insert()

      # A second active assignment for the same pair violates the partial unique index.
      assert {:error, changeset} =
               %ProgramStaffAssignment{}
               |> ProgramStaffAssignment.create_changeset(attrs)
               |> Repo.insert()

      refute changeset.valid?

      # Unassigning the first lifts the constraint (unassigned_at IS NULL no longer holds).
      {:ok, _} =
        first
        |> ProgramStaffAssignment.unassign_changeset()
        |> Repo.update()

      assert {:ok, %ProgramStaffAssignment{}} =
               %ProgramStaffAssignment{}
               |> ProgramStaffAssignment.create_changeset(attrs)
               |> Repo.insert()
    end
  end
end
