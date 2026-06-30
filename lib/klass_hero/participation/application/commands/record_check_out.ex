defmodule KlassHero.Participation.Application.Commands.RecordCheckOut do
  @moduledoc """
  Use case for checking out a child from a session.

  ## Business Rules

  - Child must be checked in to the session
  - Child must be in :checked_in status
  - Records who performed the check-out and optional notes

  ## Events Published

  - `child_checked_out` on successful check-out
  """

  alias KlassHero.Participation.Application.Shared
  alias KlassHero.Participation.Domain.Events.ParticipationEvents
  alias KlassHero.Participation.ParticipationRecord

  @type params :: %{
          required(:record_id) => String.t(),
          required(:checked_out_by) => String.t(),
          optional(:notes) => String.t()
        }

  @type result :: {:ok, ParticipationRecord.t()} | {:error, term()}

  @doc """
  Checks out a child from a session.

  ## Parameters

  - `params` - Map containing:
    - `record_id` - ID of the participation record
    - `checked_out_by` - ID of the user performing check-out
    - `notes` - Optional check-out notes

  ## Returns

  - `{:ok, record}` on success
  - `{:error, :not_found}` if record doesn't exist
  - `{:error, :invalid_status_transition}` if not in :checked_in status
  """
  @spec execute(params()) :: result()
  def execute(%{record_id: record_id, checked_out_by: checked_out_by} = params) do
    Shared.run_attendance_action(
      record_id,
      checked_out_by,
      Map.get(params, :notes),
      &ParticipationRecord.check_out/3,
      &ParticipationEvents.child_checked_out/2
    )
  end
end
