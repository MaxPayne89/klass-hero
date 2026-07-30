defmodule KlassHero.Enrollment.ConfirmEnrollmentTest do
  use KlassHero.DataCase, async: true

  import KlassHero.EventTestHelper
  import KlassHero.Factory

  alias KlassHero.Enrollment.Enrollment

  describe "execute/1" do
    test "confirms a pending enrollment owned by the provider" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      schema = insert(:enrollment_schema, program_id: program.id, status: :pending)

      assert {:ok, enrollment} =
               KlassHero.Enrollment.confirm_enrollment(%{enrollment_id: schema.id, provider_id: provider.id})

      assert %Enrollment{status: :confirmed} = enrollment
      assert enrollment.confirmed_at != nil
    end

    test "returns :unauthorized when program belongs to a different provider" do
      owner = insert(:provider_profile_schema)
      other = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: owner.id)
      schema = insert(:enrollment_schema, program_id: program.id, status: :pending)

      assert {:error, :unauthorized} =
               KlassHero.Enrollment.confirm_enrollment(%{enrollment_id: schema.id, provider_id: other.id})

      assert Enrollment.pending?(reload_enrollment(schema.id))
    end

    test "returns :not_found for unknown enrollment id" do
      provider = insert(:provider_profile_schema)

      assert {:error, :not_found} =
               KlassHero.Enrollment.confirm_enrollment(%{
                 enrollment_id: Ecto.UUID.generate(),
                 provider_id: provider.id
               })
    end

    test "returns :not_found for malformed enrollment id (no crash)" do
      provider = insert(:provider_profile_schema)

      assert {:error, :not_found} =
               KlassHero.Enrollment.confirm_enrollment(%{enrollment_id: "not-a-uuid", provider_id: provider.id})
    end

    test "returns :invalid_status_transition when already confirmed" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      schema = insert(:enrollment_schema, program_id: program.id, status: :confirmed)

      assert {:error, :invalid_status_transition} =
               KlassHero.Enrollment.confirm_enrollment(%{enrollment_id: schema.id, provider_id: provider.id})
    end

    test "returns :invalid_status_transition when cancelled" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      schema = insert(:enrollment_schema, program_id: program.id, status: :cancelled)

      assert {:error, :invalid_status_transition} =
               KlassHero.Enrollment.confirm_enrollment(%{enrollment_id: schema.id, provider_id: provider.id})
    end

    test "notifies the confirming provider's own topic, and no other" do
      provider = insert(:provider_profile_schema)
      other_provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      schema = insert(:enrollment_schema, program_id: program.id, status: :pending)

      for id <- [provider.id, other_provider.id] do
        Phoenix.PubSub.subscribe(
          KlassHero.PubSub,
          KlassHero.Enrollment.provider_scoped_topic(:enrollment_confirmed, id)
        )
      end

      assert {:ok, _} =
               KlassHero.Enrollment.confirm_enrollment(%{enrollment_id: schema.id, provider_id: provider.id})

      enrollment_id = schema.id
      assert_receive {:enrollment_confirmed, ^enrollment_id}
      refute_receive {:enrollment_confirmed, _}, 50
    end
  end

  defp reload_enrollment(id) do
    {:ok, enrollment} = KlassHero.Enrollment.get_enrollment(id)
    enrollment
  end
end
