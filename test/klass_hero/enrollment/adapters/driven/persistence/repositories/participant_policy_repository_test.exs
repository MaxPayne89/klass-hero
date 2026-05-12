defmodule KlassHero.Enrollment.Adapters.Driven.Persistence.Repositories.ParticipantPolicyRepositoryTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Enrollment.Adapters.Driven.Persistence.Repositories.ParticipantPolicyRepository

  describe "upsert/1" do
    test "creates a new participant policy" do
      program = insert(:program_schema)

      assert {:ok, policy} =
               ParticipantPolicyRepository.upsert(%{
                 program_id: program.id,
                 eligibility_at: "program_start",
                 min_age_months: 48,
                 max_age_months: 120,
                 allowed_genders: ["male", "female"],
                 min_grade: 1,
                 max_grade: 6
               })

      assert policy.program_id == to_string(program.id)
      assert policy.eligibility_at == "program_start"
      assert policy.min_age_months == 48
      assert policy.max_age_months == 120
      assert policy.allowed_genders == ["male", "female"]
      assert policy.min_grade == 1
      assert policy.max_grade == 6
    end

    test "updates existing policy on conflict" do
      program = insert(:program_schema)

      {:ok, _} =
        ParticipantPolicyRepository.upsert(%{
          program_id: program.id,
          min_age_months: 48,
          max_age_months: 120
        })

      {:ok, updated} =
        ParticipantPolicyRepository.upsert(%{
          program_id: program.id,
          min_age_months: 60,
          max_age_months: 144,
          allowed_genders: ["female"]
        })

      assert updated.min_age_months == 60
      assert updated.max_age_months == 144
      assert updated.allowed_genders == ["female"]
    end

    test "returns error changeset for invalid data" do
      assert {:error, %Ecto.Changeset{}} =
               ParticipantPolicyRepository.upsert(%{
                 max_age_months: 120
               })
    end

    test "clears all restriction fields when subsequent upsert passes nils" do
      program = insert(:program_schema)

      {:ok, _initial} =
        ParticipantPolicyRepository.upsert(%{
          program_id: program.id,
          eligibility_at: "program_start",
          min_age_months: 60,
          max_age_months: 144,
          allowed_genders: ["female"],
          min_grade: 1,
          max_grade: 4
        })

      {:ok, cleared} =
        ParticipantPolicyRepository.upsert(%{
          program_id: program.id,
          min_age_months: nil,
          max_age_months: nil,
          allowed_genders: [],
          min_grade: nil,
          max_grade: nil
        })

      assert cleared.min_age_months == nil
      assert cleared.max_age_months == nil
      assert cleared.allowed_genders == []
      assert cleared.min_grade == nil
      assert cleared.max_grade == nil
      assert cleared.eligibility_at in ["program_start", "registration"]
    end
  end

  describe "get_by_program_id/1" do
    test "returns policy when it exists" do
      program = insert(:program_schema)

      {:ok, _} =
        ParticipantPolicyRepository.upsert(%{
          program_id: program.id,
          min_age_months: 48,
          max_age_months: 120
        })

      assert {:ok, policy} = ParticipantPolicyRepository.get_by_program_id(program.id)
      assert policy.min_age_months == 48
      assert policy.max_age_months == 120
    end

    test "returns :not_found when no policy exists" do
      assert {:error, :not_found} =
               ParticipantPolicyRepository.get_by_program_id(Ecto.UUID.generate())
    end
  end

  describe "get_policies_by_program_ids/1" do
    test "returns empty map for empty list" do
      assert ParticipantPolicyRepository.get_policies_by_program_ids([]) == %{}
    end

    test "returns policies keyed by program_id" do
      program1 = insert(:program_schema)
      program2 = insert(:program_schema)

      {:ok, _} =
        ParticipantPolicyRepository.upsert(%{
          program_id: program1.id,
          min_age_months: 48,
          max_age_months: 120
        })

      {:ok, _} =
        ParticipantPolicyRepository.upsert(%{
          program_id: program2.id,
          min_grade: 1,
          max_grade: 4
        })

      result =
        ParticipantPolicyRepository.get_policies_by_program_ids([
          to_string(program1.id),
          to_string(program2.id)
        ])

      assert map_size(result) == 2
      assert result[to_string(program1.id)].min_age_months == 48
      assert result[to_string(program2.id)].min_grade == 1
    end

    test "omits programs without policies" do
      program = insert(:program_schema)
      missing_id = Ecto.UUID.generate()

      {:ok, _} =
        ParticipantPolicyRepository.upsert(%{
          program_id: program.id,
          min_age_months: 48
        })

      result =
        ParticipantPolicyRepository.get_policies_by_program_ids([
          to_string(program.id),
          missing_id
        ])

      assert map_size(result) == 1
      assert Map.has_key?(result, to_string(program.id))
      refute Map.has_key?(result, missing_id)
    end
  end
end
