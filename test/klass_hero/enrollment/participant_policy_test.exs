defmodule KlassHero.Enrollment.ParticipantPolicyTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Enrollment
  alias KlassHero.Enrollment.ParticipantPolicy

  describe "changeset/2" do
    test "is valid with just a program_id (all restrictions optional)" do
      assert ParticipantPolicy.changeset(%{program_id: Ecto.UUID.generate()}).valid?
    end

    test "requires program_id" do
      changeset = ParticipantPolicy.changeset(%{min_age_months: 60})
      refute changeset.valid?
      assert %{program_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects unknown eligibility_at" do
      changeset = ParticipantPolicy.changeset(%{program_id: Ecto.UUID.generate(), eligibility_at: "whenever"})
      refute changeset.valid?
      assert %{eligibility_at: [_]} = errors_on(changeset)
    end

    test "rejects invalid gender values" do
      changeset = ParticipantPolicy.changeset(%{program_id: Ecto.UUID.generate(), allowed_genders: ["martian"]})
      refute changeset.valid?
      assert %{allowed_genders: [_]} = errors_on(changeset)
    end

    test "rejects min age greater than max age" do
      changeset =
        ParticipantPolicy.changeset(%{program_id: Ecto.UUID.generate(), min_age_months: 120, max_age_months: 60})

      refute changeset.valid?
      assert %{min_age_months: ["must not exceed maximum age"]} = errors_on(changeset)
    end

    test "rejects grades outside 1..13" do
      refute ParticipantPolicy.changeset(%{program_id: Ecto.UUID.generate(), min_grade: 0}).valid?
      refute ParticipantPolicy.changeset(%{program_id: Ecto.UUID.generate(), max_grade: 14}).valid?
    end
  end

  describe "eligible?/2 (pure)" do
    test "eligible when all bounds satisfied" do
      policy = %ParticipantPolicy{
        min_age_months: 60,
        max_age_months: 120,
        allowed_genders: ["male"],
        min_grade: 1,
        max_grade: 6
      }

      assert {:ok, :eligible} = ParticipantPolicy.eligible?(policy, %{age_months: 80, gender: "male", grade: 3})
    end

    test "accumulates every failing reason" do
      policy = %ParticipantPolicy{min_age_months: 60, allowed_genders: ["female"], min_grade: 3, max_grade: 6}

      assert {:error, reasons} =
               ParticipantPolicy.eligible?(policy, %{age_months: 10, gender: "male", grade: 1})

      assert length(reasons) >= 3
    end

    test "no restrictions means eligible" do
      policy = %ParticipantPolicy{}
      assert {:ok, :eligible} = ParticipantPolicy.eligible?(policy, %{age_months: 80, gender: "male", grade: 3})
    end
  end

  describe "age_in_months/2 (pure)" do
    test "counts complete months, subtracting one before the birthday day" do
      assert ParticipantPolicy.age_in_months(~D[2018-06-15], ~D[2024-06-15]) == 72
      assert ParticipantPolicy.age_in_months(~D[2018-06-15], ~D[2024-06-14]) == 71
      assert ParticipantPolicy.age_in_months(~D[2024-01-01], ~D[2023-01-01]) == 0
    end
  end

  describe "set_participant_policy/1 (upsert) + get_participant_policy/1" do
    test "creates a new policy and reads it back" do
      program = insert(:program_schema)

      assert {:ok, %ParticipantPolicy{} = policy} =
               Enrollment.set_participant_policy(%{program_id: program.id, min_age_months: 72, max_age_months: 144})

      assert policy.program_id == program.id
      assert {:ok, ^policy} = Enrollment.get_participant_policy(program.id)
    end

    test "upserts on the same program_id rather than duplicating" do
      program = insert(:program_schema)

      {:ok, _} = Enrollment.set_participant_policy(%{program_id: program.id, min_age_months: 48})

      {:ok, updated} =
        Enrollment.set_participant_policy(%{program_id: program.id, min_age_months: 96, max_age_months: 168})

      assert updated.min_age_months == 96
      assert updated.max_age_months == 168
    end

    test "returns an error changeset on missing program_id" do
      assert {:error, %Ecto.Changeset{}} = Enrollment.set_participant_policy(%{min_age_months: 48})
    end

    test "get_participant_policy/1 returns {:error, :not_found} for an unknown program" do
      assert {:error, :not_found} = Enrollment.get_participant_policy(Ecto.UUID.generate())
    end
  end
end
