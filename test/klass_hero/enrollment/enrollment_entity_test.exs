defmodule KlassHero.Enrollment.EnrollmentEntityTest do
  use ExUnit.Case, async: true

  alias KlassHero.Enrollment.Enrollment

  describe "create_changeset/2" do
    test "is valid with all required fields" do
      assert Enrollment.create_changeset(valid_attrs()).valid?
    end

    test "requires program_id, parent_id, child_id, status, enrolled_at" do
      changeset = Enrollment.create_changeset(%{})
      errors = errors_on(changeset)

      for field <- [:program_id, :parent_id, :child_id, :status, :enrolled_at] do
        assert Map.has_key?(errors, field), "expected #{field} to be required"
      end
    end

    test "rejects an unknown payment_method but allows nil" do
      refute Enrollment.create_changeset(Map.put(valid_attrs(), :payment_method, "bitcoin")).valid?
      assert Enrollment.create_changeset(Map.put(valid_attrs(), :payment_method, nil)).valid?
    end

    test "accepts card and transfer payment methods" do
      for method <- ["card", "transfer"] do
        assert Enrollment.create_changeset(Map.put(valid_attrs(), :payment_method, method)).valid?
      end
    end

    test "rejects negative fee amounts" do
      refute Enrollment.create_changeset(Map.put(valid_attrs(), :subtotal, -1)).valid?
    end
  end

  describe "confirm/1" do
    test "confirms a pending enrollment" do
      assert {:ok, confirmed} = Enrollment.confirm(enrollment(:pending))
      assert confirmed.status == :confirmed
      assert is_struct(confirmed.confirmed_at, DateTime)
    end

    test "rejects a non-pending enrollment" do
      assert {:error, :invalid_status_transition} = Enrollment.confirm(enrollment(:confirmed))
    end
  end

  describe "complete/1" do
    test "completes a confirmed enrollment" do
      assert {:ok, completed} = Enrollment.complete(enrollment(:confirmed))
      assert completed.status == :completed
      assert is_struct(completed.completed_at, DateTime)
    end

    test "rejects a non-confirmed enrollment" do
      assert {:error, :invalid_status_transition} = Enrollment.complete(enrollment(:pending))
    end
  end

  describe "cancel/2" do
    test "cancels a pending enrollment with a reason" do
      assert {:ok, cancelled} = Enrollment.cancel(enrollment(:pending), "Changed mind")
      assert cancelled.status == :cancelled
      assert is_struct(cancelled.cancelled_at, DateTime)
      assert cancelled.cancellation_reason == "Changed mind"
    end

    test "cancels a confirmed enrollment" do
      assert {:ok, cancelled} = Enrollment.cancel(enrollment(:confirmed))
      assert cancelled.status == :cancelled
    end

    test "rejects completed or cancelled enrollments" do
      assert {:error, :invalid_status_transition} = Enrollment.cancel(enrollment(:completed))
      assert {:error, :invalid_status_transition} = Enrollment.cancel(enrollment(:cancelled))
    end
  end

  describe "ensure_reason_present/1" do
    test "accepts a non-empty binary, rejects empty and nil" do
      assert {:ok, "Parent requested"} = Enrollment.ensure_reason_present("Parent requested")
      assert {:error, :invalid_reason} = Enrollment.ensure_reason_present("")
      assert {:error, :invalid_reason} = Enrollment.ensure_reason_present(nil)
    end
  end

  describe "predicates" do
    test "status predicates" do
      assert Enrollment.pending?(enrollment(:pending))
      assert Enrollment.confirmed?(enrollment(:confirmed))
      assert Enrollment.completed?(enrollment(:completed))
      assert Enrollment.cancelled?(enrollment(:cancelled))
    end

    test "active?/1 is true only for pending or confirmed" do
      assert Enrollment.active?(enrollment(:pending))
      assert Enrollment.active?(enrollment(:confirmed))
      refute Enrollment.active?(enrollment(:completed))
      refute Enrollment.active?(enrollment(:cancelled))
    end
  end

  describe "constants" do
    test "valid_statuses/0 and valid_payment_methods/0" do
      assert Enrollment.valid_statuses() == [:pending, :confirmed, :completed, :cancelled]
      assert Enrollment.valid_payment_methods() == ["card", "transfer"]
    end
  end

  defp valid_attrs do
    %{
      program_id: Ecto.UUID.generate(),
      child_id: Ecto.UUID.generate(),
      parent_id: Ecto.UUID.generate(),
      status: :pending,
      enrolled_at: DateTime.utc_now()
    }
  end

  defp enrollment(status) do
    %Enrollment{
      id: Ecto.UUID.generate(),
      program_id: Ecto.UUID.generate(),
      child_id: Ecto.UUID.generate(),
      parent_id: Ecto.UUID.generate(),
      status: status,
      enrolled_at: DateTime.utc_now()
    }
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
