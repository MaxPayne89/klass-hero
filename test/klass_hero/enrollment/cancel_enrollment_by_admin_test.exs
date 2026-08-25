defmodule KlassHero.Enrollment.CancelEnrollmentByAdminTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Enrollment.Enrollment

  describe "execute/3" do
    test "cancels a pending enrollment and returns domain entity" do
      schema = insert(:enrollment_schema, status: :pending)
      admin_id = Ecto.UUID.generate()

      assert {:ok, enrollment} =
               KlassHero.Enrollment.cancel_enrollment_by_admin(schema.id, admin_id, "Duplicate booking")

      assert %Enrollment{} = enrollment
      assert enrollment.status == :cancelled
      assert enrollment.cancellation_reason == "Duplicate booking"
      assert %DateTime{} = enrollment.cancelled_at
    end

    test "cancels a confirmed enrollment" do
      schema = insert(:enrollment_schema, status: :confirmed)
      admin_id = Ecto.UUID.generate()

      assert {:ok, enrollment} =
               KlassHero.Enrollment.cancel_enrollment_by_admin(schema.id, admin_id, "Parent requested")

      assert enrollment.status == :cancelled
    end

    test "returns invalid_status_transition for completed enrollment" do
      schema = insert(:enrollment_schema, status: :completed)
      admin_id = Ecto.UUID.generate()

      assert {:error, :invalid_status_transition} =
               KlassHero.Enrollment.cancel_enrollment_by_admin(schema.id, admin_id, "Too late")
    end

    test "returns invalid_status_transition for already cancelled enrollment" do
      schema = insert(:enrollment_schema, status: :cancelled)
      admin_id = Ecto.UUID.generate()

      assert {:error, :invalid_status_transition} =
               KlassHero.Enrollment.cancel_enrollment_by_admin(schema.id, admin_id, "Already gone")
    end

    test "returns not_found for nonexistent enrollment" do
      admin_id = Ecto.UUID.generate()

      assert {:error, :not_found} =
               KlassHero.Enrollment.cancel_enrollment_by_admin(Ecto.UUID.generate(), admin_id, "Nope")
    end

    test "returns invalid_reason for empty reason" do
      schema = insert(:enrollment_schema, status: :pending)
      admin_id = Ecto.UUID.generate()

      assert {:error, :invalid_reason} =
               KlassHero.Enrollment.cancel_enrollment_by_admin(schema.id, admin_id, "")
    end

    test "returns invalid_reason for nil reason" do
      schema = insert(:enrollment_schema, status: :pending)
      admin_id = Ecto.UUID.generate()

      assert {:error, :invalid_reason} =
               KlassHero.Enrollment.cancel_enrollment_by_admin(schema.id, admin_id, nil)
    end
  end
end
