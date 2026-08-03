defmodule KlassHero.Messaging.StaffParticipants do
  @moduledoc """
  Reads and writes over `program_staff_participants` — Messaging's mirror of which
  staff are active on a program.

  Writes come from `StaffAssignmentHandler` reacting to Provider integration
  events; reads resolve broadcast and conversation recipients. Callers reach
  these through `KlassHero.Messaging`'s public API or, within the context,
  directly — this module is internal to Messaging.

  Every operation is wrapped in a `db_interaction` span, so the three DB calls
  stay individually traceable rather than disappearing into their callers.
  """

  use KlassHero.Shared.Interaction

  import Ecto.Query

  alias KlassHero.Messaging.ProgramStaffParticipant
  alias KlassHero.Repo

  @doc "Lists the user IDs of staff currently active on the given program."
  @spec get_active_staff_user_ids(String.t()) :: [String.t()]
  def get_active_staff_user_ids(program_id) do
    db_interaction operation: :get_active_staff_user_ids, entity: "program_staff_participant" do
      ProgramStaffParticipant
      |> where([p], p.program_id == ^program_id and p.active == true)
      |> select([p], p.staff_user_id)
      |> Repo.all()
    end
  end

  @doc """
  Marks a staff member active on a program, inserting the row if absent.

  Re-assignment after removal reactivates the existing row rather than creating a
  second one — the `{program_id, staff_user_id}` conflict target is what makes
  repeated `staff_assigned_to_program` events idempotent.
  """
  @spec upsert_active(map()) :: :ok | {:error, Ecto.Changeset.t()}
  def upsert_active(attrs) do
    db_interaction operation: :upsert_active, entity: "program_staff_participant" do
      %ProgramStaffParticipant{}
      |> ProgramStaffParticipant.changeset(Map.put(attrs, :active, true))
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

  @doc "Marks a staff member inactive on a program. Unknown pairs are a no-op."
  @spec deactivate(String.t(), String.t()) :: :ok
  def deactivate(program_id, staff_user_id) do
    db_interaction operation: :deactivate, entity: "program_staff_participant" do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      from(p in ProgramStaffParticipant,
        where: p.program_id == ^program_id and p.staff_user_id == ^staff_user_id
      )
      |> Repo.update_all(set: [active: false, updated_at: now])

      :ok
    end
  end
end
