defmodule KlassHero.Messaging.Application.Commands.ScheduleEmailContentFetch do
  @moduledoc """
  Command for scheduling a content fetch retry for an inbound email.
  """

  alias KlassHero.Messaging.Adapters.Driving.Workers.FetchEmailContentWorker

  @doc """
  Schedules a content fetch for an inbound email.

  ## Parameters
  - email_id: The inbound email ID
  - resend_id: The Resend email ID for the API call

  ## Returns
  - `{:ok, term()}` - Job scheduled
  - `{:error, reason}` - Scheduling failed
  """
  @spec execute(String.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def execute(email_id, resend_id) do
    %{email_id: email_id, resend_id: resend_id}
    |> FetchEmailContentWorker.new()
    |> Oban.insert()
  end
end
