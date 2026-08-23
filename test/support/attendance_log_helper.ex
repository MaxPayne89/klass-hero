defmodule KlassHero.AttendanceLogHelper do
  @moduledoc """
  Reading the attendance transition log in tests.

  Every attendance verb appends to `attendance_transitions` (#1329), so the same
  assertion belongs in every verb's test file — and looking the same everywhere
  is the point. A verb that quietly stops logging should fail a test that reads
  identically to its siblings', not slip through because each file checked
  something slightly different.
  """

  import Ecto.Query

  alias KlassHero.Participation.AttendanceTransition
  alias KlassHero.Repo

  @doc """
  Every transition logged for `record_id`, oldest first.

  Two transitions inside the same second are not ordered relative to each other
  — assert on their content, not their position.
  """
  @spec transitions_for(String.t()) :: [AttendanceTransition.t()]
  def transitions_for(record_id) do
    Repo.all(from t in AttendanceTransition, where: t.record_id == ^record_id, order_by: t.occurred_at)
  end

  @doc """
  The one transition logged for `record_id`, or `nil` if the write was refused.

  Raises on more than one: a verb that logs twice is a bug this helper should
  surface, not average away.
  """
  @spec only_transition(String.t()) :: AttendanceTransition.t() | nil
  def only_transition(record_id) do
    case transitions_for(record_id) do
      [] -> nil
      [one] -> one
      many -> raise "expected at most one transition for #{record_id}, found #{length(many)}"
    end
  end
end
