defmodule KlassHeroWeb.Admin.Actions.CancelBookingActionTest do
  use KlassHero.DataCase, async: true

  # These exercise functions that *return* a socket or conn, so their assigns are the
  # return value under test — there is no rendered page to assert against instead.
  import Ecto.Changeset
  import KlassHero.Factory

  alias KlassHero.Accounts.Scope
  alias KlassHero.AccountsFixtures
  alias KlassHeroWeb.Admin.Actions.CancelBookingAction
  alias Phoenix.LiveView.Socket

  @moduletag :plug_test

  describe "changeset/3" do
    setup do
      base = {%{}, %{reason: :string}}
      %{base: base}
    end

    test "requires reason", %{base: base} do
      changeset = CancelBookingAction.changeset(base, %{}, %{})

      refute changeset.valid?
      assert errors_on(changeset).reason == ["can't be blank"]
    end

    test "rejects reason exceeding 1000 characters", %{base: base} do
      long_reason = String.duplicate("a", 1001)
      changeset = CancelBookingAction.changeset(base, %{reason: long_reason}, %{})

      refute changeset.valid?

      assert errors_on(changeset).reason == [
               "should be at most 1000 character(s)"
             ]
    end

    test "accepts valid reason", %{base: base} do
      changeset = CancelBookingAction.changeset(base, %{reason: "Duplicate booking"}, %{})

      assert changeset.valid?
      assert get_change(changeset, :reason) == "Duplicate booking"
    end

    test "accepts reason at exactly 1000 characters", %{base: base} do
      reason = String.duplicate("a", 1000)
      changeset = CancelBookingAction.changeset(base, %{reason: reason}, %{})

      assert changeset.valid?
    end
  end

  describe "handle/3" do
    setup do
      admin = AccountsFixtures.user_fixture(%{is_admin: true})
      scope = Scope.for_user(admin)

      socket = %Socket{
        assigns: %{
          __changed__: %{},
          flash: %{},
          current_scope: scope
        },
        private: %{live_temp: %{}}
      }

      %{socket: socket, admin: admin}
    end

    test "all items cancelled — info flash with count", %{socket: socket} do
      e1 = insert(:enrollment_schema, status: "pending")
      e2 = insert(:enrollment_schema, status: "confirmed")

      items = [%{id: e1.id}, %{id: e2.id}]
      data = %{reason: "Batch cleanup"}

      assert {:ok, result_socket} = CancelBookingAction.handle(socket, items, data)
      assert result_socket.assigns.flash["info"] == "2 booking(s) cancelled successfully."
    end

    test "single item cancelled — info flash", %{socket: socket} do
      enrollment = insert(:enrollment_schema, status: "pending")

      items = [%{id: enrollment.id}]
      data = %{reason: "Parent requested"}

      assert {:ok, result_socket} = CancelBookingAction.handle(socket, items, data)
      assert result_socket.assigns.flash["info"] == "1 booking(s) cancelled successfully."
    end

    test "all items fail — error flash with count", %{socket: socket} do
      e1 = insert(:enrollment_schema, status: "completed")
      e2 = insert(:enrollment_schema, status: "cancelled")

      items = [%{id: e1.id}, %{id: e2.id}]
      data = %{reason: "Too late"}

      assert {:ok, result_socket} = CancelBookingAction.handle(socket, items, data)
      assert result_socket.assigns.flash["error"] == "Could not cancel 2 booking(s)."
    end

    test "partial failure — warning flash with counts", %{socket: socket} do
      ok_enrollment = insert(:enrollment_schema, status: "pending")
      bad_enrollment = insert(:enrollment_schema, status: "completed")

      items = [%{id: ok_enrollment.id}, %{id: bad_enrollment.id}]
      data = %{reason: "Mixed batch"}

      assert {:ok, result_socket} = CancelBookingAction.handle(socket, items, data)

      assert result_socket.assigns.flash["warning"] ==
               "1 of 2 booking(s) cancelled. 1 could not be cancelled."
    end

    test "nonexistent enrollment counted as failure", %{socket: socket} do
      items = [%{id: Ecto.UUID.generate()}]
      data = %{reason: "Ghost booking"}

      assert {:ok, result_socket} = CancelBookingAction.handle(socket, items, data)
      assert result_socket.assigns.flash["error"] == "Could not cancel 1 booking(s)."
    end
  end
end
