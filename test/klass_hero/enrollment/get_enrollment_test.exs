defmodule KlassHero.Enrollment.GetEnrollmentTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Enrollment.Enrollment

  describe "execute/1" do
    test "returns enrollment when found" do
      enrollment_schema = insert(:enrollment_schema)

      assert {:ok, enrollment} = KlassHero.Enrollment.get_enrollment(enrollment_schema.id)
      assert %Enrollment{} = enrollment
      assert enrollment.id == to_string(enrollment_schema.id)
    end

    test "returns domain entity with all fields" do
      enrollment_schema =
        insert(:enrollment_schema,
          status: "confirmed",
          subtotal: Decimal.new("150.00"),
          vat_amount: Decimal.new("28.50"),
          payment_method: "transfer",
          special_requirements: "Needs wheelchair access"
        )

      {:ok, enrollment} = KlassHero.Enrollment.get_enrollment(enrollment_schema.id)

      assert enrollment.status == :confirmed
      assert enrollment.subtotal == Decimal.new("150.00")
      assert enrollment.vat_amount == Decimal.new("28.50")
      assert enrollment.payment_method == "transfer"
      assert enrollment.special_requirements == "Needs wheelchair access"
    end

    test "returns not_found when enrollment does not exist" do
      non_existent_id = Ecto.UUID.generate()

      assert {:error, :not_found} = KlassHero.Enrollment.get_enrollment(non_existent_id)
    end

    test "converts status from string to atom" do
      for status <- ["pending", "confirmed", "completed", "cancelled"] do
        enrollment_schema = insert(:enrollment_schema, status: status)

        {:ok, enrollment} = KlassHero.Enrollment.get_enrollment(enrollment_schema.id)

        assert enrollment.status == String.to_atom(status)
      end
    end

    test "returns string IDs" do
      enrollment_schema = insert(:enrollment_schema)

      {:ok, enrollment} = KlassHero.Enrollment.get_enrollment(enrollment_schema.id)

      assert is_binary(enrollment.id)
      assert is_binary(enrollment.program_id)
      assert is_binary(enrollment.child_id)
      assert is_binary(enrollment.parent_id)
    end
  end
end
