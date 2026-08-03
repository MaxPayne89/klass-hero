defmodule KlassHero.Messaging.StaffParticipantsTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.Messaging.StaffParticipants

  @provider_id Ecto.UUID.generate()
  @program_id Ecto.UUID.generate()

  describe "upsert_active/1" do
    test "inserts new active staff participant" do
      staff_user_id = Ecto.UUID.generate()

      assert :ok =
               StaffParticipants.upsert_active(%{
                 provider_id: @provider_id,
                 program_id: @program_id,
                 staff_user_id: staff_user_id
               })

      assert [^staff_user_id] =
               StaffParticipants.get_active_staff_user_ids(@program_id)
    end

    test "reactivates previously deactivated participant" do
      staff_user_id = Ecto.UUID.generate()
      attrs = %{provider_id: @provider_id, program_id: @program_id, staff_user_id: staff_user_id}

      :ok = StaffParticipants.upsert_active(attrs)
      :ok = StaffParticipants.deactivate(@program_id, staff_user_id)
      assert [] = StaffParticipants.get_active_staff_user_ids(@program_id)

      :ok = StaffParticipants.upsert_active(attrs)

      assert [^staff_user_id] =
               StaffParticipants.get_active_staff_user_ids(@program_id)
    end
  end

  describe "deactivate/2" do
    test "marks staff participant as inactive" do
      staff_user_id = Ecto.UUID.generate()

      :ok =
        StaffParticipants.upsert_active(%{
          provider_id: @provider_id,
          program_id: @program_id,
          staff_user_id: staff_user_id
        })

      :ok = StaffParticipants.deactivate(@program_id, staff_user_id)
      assert [] = StaffParticipants.get_active_staff_user_ids(@program_id)
    end

    test "is a no-op for non-existent participant" do
      assert :ok =
               StaffParticipants.deactivate(
                 Ecto.UUID.generate(),
                 Ecto.UUID.generate()
               )
    end
  end

  describe "get_active_staff_user_ids/1" do
    test "returns only active staff for program" do
      staff1 = Ecto.UUID.generate()
      staff2 = Ecto.UUID.generate()

      :ok =
        StaffParticipants.upsert_active(%{
          provider_id: @provider_id,
          program_id: @program_id,
          staff_user_id: staff1
        })

      :ok =
        StaffParticipants.upsert_active(%{
          provider_id: @provider_id,
          program_id: @program_id,
          staff_user_id: staff2
        })

      :ok = StaffParticipants.deactivate(@program_id, staff2)

      active = StaffParticipants.get_active_staff_user_ids(@program_id)
      assert active == [staff1]
    end
  end
end
