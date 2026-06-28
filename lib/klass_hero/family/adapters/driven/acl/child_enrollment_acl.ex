defmodule KlassHero.Family.Adapters.Driven.ACL.ChildEnrollmentACL do
  @moduledoc """
  ACL adapter that manages enrollment data for child deletion.

  Queries the `enrollments` and `programs` tables directly to avoid
  a dependency cycle (Enrollment already depends on Family).
  """

  use KlassHero.Shared.Tracing

  import Ecto.Query, only: [from: 2]

  alias KlassHero.Repo

  @active_statuses ~w(pending confirmed)

  def list_active_with_program_titles(child_id) when is_binary(child_id) do
    acl_span source: "family", target: "enrollment" do
      from(e in "enrollments",
        join: p in "programs",
        on: e.program_id == p.id,
        where: e.child_id == type(^child_id, :binary_id),
        where: e.status in ^@active_statuses,
        select: %{
          enrollment_id: type(e.id, :binary_id),
          program_id: type(e.program_id, :binary_id),
          program_title: p.title,
          status: e.status
        }
      )
      |> Repo.all()
    end
  end

  def cancel_active_for_child(child_id) when is_binary(child_id) do
    acl_span source: "family", target: "enrollment" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {count, _} =
        from(e in "enrollments",
          where: e.child_id == type(^child_id, :binary_id),
          where: e.status in ^@active_statuses
        )
        |> Repo.update_all(
          set: [
            status: "cancelled",
            cancellation_reason: "child_deleted",
            cancelled_at: now,
            updated_at: now
          ]
        )

      {:ok, count}
    end
  end
end
