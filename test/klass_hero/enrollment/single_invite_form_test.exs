defmodule KlassHero.Enrollment.SingleInviteFormTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.Enrollment.SingleInviteForm

  @valid_attrs %{
    "program_id" => "11111111-1111-1111-1111-111111111111",
    "child_first_name" => "Emma",
    "child_last_name" => "Schmidt",
    "child_date_of_birth" => "2016-03-15",
    "guardian_email" => "parent@example.com"
  }

  describe "changeset/2" do
    test "is valid with the minimum required fields" do
      changeset = SingleInviteForm.changeset(@valid_attrs)
      assert changeset.valid?
    end

    test "reports required-field errors when blank" do
      changeset = SingleInviteForm.changeset(%{})

      errors = errors_on(changeset)
      assert errors[:program_id] == ["can't be blank"]
      assert errors[:child_first_name] == ["can't be blank"]
      assert errors[:child_last_name] == ["can't be blank"]
      assert errors[:child_date_of_birth] == ["can't be blank"]
      assert errors[:guardian_email] == ["can't be blank"]
    end

    test "rejects malformed guardian email" do
      changeset = SingleInviteForm.changeset(Map.put(@valid_attrs, "guardian_email", "not-an-email"))

      refute changeset.valid?
      assert errors_on(changeset)[:guardian_email] == ["must be a valid email"]
    end

    test "rejects guardian2_email when provided but invalid" do
      changeset =
        SingleInviteForm.changeset(Map.put(@valid_attrs, "guardian2_email", "nope"))

      assert errors_on(changeset)[:guardian2_email] == ["must be a valid email"]
    end

    test "accepts empty guardian2_email (optional second guardian)" do
      changeset = SingleInviteForm.changeset(Map.put(@valid_attrs, "guardian2_email", ""))
      assert changeset.valid?
    end

    test "rejects future date of birth" do
      future = Date.utc_today() |> Date.add(1) |> Date.to_iso8601()

      changeset =
        SingleInviteForm.changeset(Map.put(@valid_attrs, "child_date_of_birth", future))

      assert errors_on(changeset)[:child_date_of_birth] == ["must be in the past"]
    end

    test "rejects school_grade outside 1..13" do
      changeset = SingleInviteForm.changeset(Map.put(@valid_attrs, "school_grade", "14"))
      assert errors_on(changeset)[:school_grade]
    end
  end

  describe "to_invite_row/1" do
    test "returns the persistence-ready attribute map for a valid changeset" do
      {:ok, row} =
        @valid_attrs
        |> SingleInviteForm.changeset()
        |> SingleInviteForm.to_invite_row()

      assert row.child_first_name == "Emma"
      assert row.guardian_email == "parent@example.com"
      assert row.child_date_of_birth == ~D[2016-03-15]
      # provider_id is set by the command from the current scope, not the form
      assert row.provider_id == nil
    end

    test "returns {:error, changeset} for an invalid changeset" do
      assert {:error, %Ecto.Changeset{valid?: false}} =
               %{} |> SingleInviteForm.changeset() |> SingleInviteForm.to_invite_row()
    end
  end

  describe "apply_domain_errors/2" do
    test "adds each field error onto the changeset with :action=:validate" do
      changeset = SingleInviteForm.changeset(@valid_attrs)

      updated =
        SingleInviteForm.apply_domain_errors(changeset, [
          {:program_id, "does not belong to this provider"},
          {:guardian_email, "already invited for this program"}
        ])

      assert updated.action == :validate
      errors = errors_on(updated)
      assert errors[:program_id] == ["does not belong to this provider"]
      assert errors[:guardian_email] == ["already invited for this program"]
    end
  end
end
