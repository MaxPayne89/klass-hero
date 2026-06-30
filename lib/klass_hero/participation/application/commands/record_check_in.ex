defmodule KlassHero.Participation.Application.Commands.RecordCheckIn do
  @moduledoc """
  Use case for checking in a child to a session.

  ## Business Rules

  - Child must be registered for the session
  - Child must be in :registered status
  - Records who performed the check-in and optional notes

  ## Events Published

  - `child_checked_in` on successful check-in
  """

  alias KlassHero.Participation.Application.Shared
  alias KlassHero.Participation.Domain.Events.ParticipationEvents
  alias KlassHero.Participation.ParticipationRecord

  @type params :: %{
          required(:record_id) => String.t(),
          required(:checked_in_by) => String.t(),
          optional(:notes) => String.t()
        }

  @type result :: {:ok, ParticipationRecord.t()} | {:error, term()}

  @doc """
  Checks in a child to a session.

  ## Parameters

  - `params` - Map containing:
    - `record_id` - ID of the participation record
    - `checked_in_by` - ID of the user performing check-in
    - `notes` - Optional check-in notes

  ## Returns

  - `{:ok, record}` on success
  - `{:error, :not_found}` if record doesn't exist
  - `{:error, :invalid_status_transition}` if not in :registered status
  """
  @spec execute(params()) :: result()
  def execute(%{record_id: record_id, checked_in_by: checked_in_by} = params) do
    Shared.run_attendance_action(
      record_id,
      checked_in_by,
      Map.get(params, :notes),
      &ParticipationRecord.check_in/3,
      &ParticipationEvents.child_checked_in/2
    )
  end
end
