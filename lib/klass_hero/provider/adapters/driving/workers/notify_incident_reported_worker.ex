defmodule KlassHero.Provider.Adapters.Driving.Workers.NotifyIncidentReportedWorker do
  @moduledoc """
  Oban worker that delivers the incident-report email for a single report.

  Runs on the `:email` queue (concurrency 1) so Resend rate limits are
  respected globally. Delegates the actual orchestration to the
  `NotifyIncidentReported` use case.
  """

  use KlassHero.Shared.RateLimitedEmailWorker, queue: :email, max_attempts: 3

  alias KlassHero.Provider.NotifyIncidentReported

  defguardp is_present(s) when is_binary(s) and byte_size(s) > 0

  @impl true
  def execute(%Oban.Job{
        args: %{"incident_report_id" => id, "business_owner_email" => owner_email, "business_name" => business_name}
      })
      when is_present(id) and is_present(owner_email) and is_present(business_name) do
    NotifyIncidentReported.execute(%{
      incident_report_id: id,
      business_owner_email: owner_email,
      business_name: business_name
    })
  end
end
