defmodule KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.ProgramStaffParticipantRepository do
  @moduledoc """
  Ecto-based repository for the program_staff_participants projection table.

  Plain module (called by fixed name — no port/behaviour). Kept in sync by
  integration events from the Provider context via the messaging integration
  event handler, and read by the messaging commands that resolve active staff.
  """

  use KlassHero.Shared.Interaction

  import Ecto.Query

  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.ProgramStaffParticipantSchema
  alias KlassHero.Repo

  def get_active_staff_user_ids(program_id) do
    db_interaction operation: :get_active_staff_user_ids, entity: "program_staff_participant" do
      ProgramStaffParticipantSchema
      |> where([p], p.program_id == ^program_id and p.active == true)
      |> select([p], p.staff_user_id)
      |> Repo.all()
    end
  end

  def upsert_active(attrs) do
    db_interaction operation: :upsert_active, entity: "program_staff_participant" do
      %ProgramStaffParticipantSchema{}
      |> ProgramStaffParticipantSchema.changeset(Map.put(attrs, :active, true))
      |> Repo.insert(
        on_conflict: [
          set: [
            active: true,
            updated_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
          ]
        ],
        conflict_target: [:program_id, :staff_user_id]
      )
      |> case do
        {:ok, _} -> :ok
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  def deactivate(program_id, staff_user_id) do
    db_interaction operation: :deactivate, entity: "program_staff_participant" do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      from(p in ProgramStaffParticipantSchema,
        where: p.program_id == ^program_id and p.staff_user_id == ^staff_user_id
      )
      |> Repo.update_all(set: [active: false, updated_at: now])

      :ok
    end
  end
end
