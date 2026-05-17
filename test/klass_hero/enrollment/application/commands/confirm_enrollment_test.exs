defmodule KlassHero.Enrollment.Application.Commands.ConfirmEnrollmentTest do
  use KlassHero.DataCase, async: true

  import KlassHero.EventTestHelper
  import KlassHero.Factory

  alias KlassHero.Enrollment.Application.Commands.ConfirmEnrollment
  alias KlassHero.Enrollment.Domain.Models.Enrollment

  describe "execute/1" do
    test "confirms a pending enrollment owned by the provider" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      schema = insert(:enrollment_schema, program_id: program.id, status: :pending)

      assert {:ok, enrollment} =
               ConfirmEnrollment.execute(%{enrollment_id: schema.id, provider_id: provider.id})

      assert %Enrollment{status: :confirmed} = enrollment
      assert enrollment.confirmed_at != nil
    end

    test "returns :unauthorized when program belongs to a different provider" do
      owner = insert(:provider_profile_schema)
      other = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: owner.id)
      schema = insert(:enrollment_schema, program_id: program.id, status: :pending)

      assert {:error, :unauthorized} =
               ConfirmEnrollment.execute(%{enrollment_id: schema.id, provider_id: other.id})

      assert Enrollment.pending?(reload_enrollment(schema.id))
    end

    test "returns :not_found for unknown enrollment id" do
      provider = insert(:provider_profile_schema)

      assert {:error, :not_found} =
               ConfirmEnrollment.execute(%{
                 enrollment_id: Ecto.UUID.generate(),
                 provider_id: provider.id
               })
    end

    test "returns :invalid_status_transition when already confirmed" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      schema = insert(:enrollment_schema, program_id: program.id, status: :confirmed)

      assert {:error, :invalid_status_transition} =
               ConfirmEnrollment.execute(%{enrollment_id: schema.id, provider_id: provider.id})
    end

    test "returns :invalid_status_transition when cancelled" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      schema = insert(:enrollment_schema, program_id: program.id, status: :cancelled)

      assert {:error, :invalid_status_transition} =
               ConfirmEnrollment.execute(%{enrollment_id: schema.id, provider_id: provider.id})
    end

    test "publishes an :enrollment_confirmed event on success" do
      setup_test_events()

      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      schema = insert(:enrollment_schema, program_id: program.id, status: :pending)

      assert {:ok, _} =
               ConfirmEnrollment.execute(%{enrollment_id: schema.id, provider_id: provider.id})

      event = assert_event_published(:enrollment_confirmed)
      assert event.aggregate_id == schema.id
    end
  end

  defp reload_enrollment(id) do
    {:ok, enrollment} = KlassHero.Enrollment.get_enrollment(id)
    enrollment
  end
end
