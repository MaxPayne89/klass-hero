defmodule KlassHero.Family.Adapters.Driven.ACL.ChildParticipationACL do
  @moduledoc """
  ACL adapter that cleans up participation data for child deletion.

  Deletes behavioral notes and participation records directly to avoid
  a dependency cycle (Participation already depends on Family).

  Behavioral notes must be deleted before participation records because
  behavioral_notes.child_id has an ON DELETE: nothing FK constraint that
  would block child deletion.
  """

  @behaviour KlassHero.Family.Domain.Ports.ForManagingChildParticipation

  use KlassHero.Shared.Tracing

  import Ecto.Query, only: [from: 2]

  alias KlassHero.Repo

  @impl true
  def delete_all_for_child(child_id) when is_binary(child_id) do
    acl_span source: "family", target: "participation" do
      # behavioral_notes.child_id has ON DELETE: nothing — must delete notes first
      {notes_count, _} =
        from(n in "behavioral_notes",
          where: n.child_id == type(^child_id, :binary_id)
        )
        |> Repo.delete_all()

      {records_count, _} =
        from(r in "participation_records",
          where: r.child_id == type(^child_id, :binary_id)
        )
        |> Repo.delete_all()

      {:ok, %{participation_records: records_count, behavioral_notes: notes_count}}
    end
  end
end
