defmodule KlassHero.Provider.NotifyIncidentReported do
  @moduledoc """
  Emails a provider's business owner when an incident report is submitted.

  Payload-driven: `business_owner_email` and `business_name` arrive in the args
  map (forwarded by `NotifyIncidentReportedWorker` from the enqueued Oban job).
  No `ProviderProfile` lookup happens here — that responsibility is upstream in
  `SubmitIncidentReport`, which loads the profile once and threads the two
  fields through the enqueue.
  """

  alias KlassHero.Provider
  alias KlassHero.Provider.Adapters.Driven.Notifications.IncidentReportedEmailNotifier
  alias KlassHero.Provider.IncidentReport
  alias KlassHero.Provider.Programs
  alias KlassHero.Shared.Storage

  require Logger

  @signed_url_ttl_seconds 3600
  @program_fallback_label "a program"
  @session_fallback_label "a session"

  defguardp is_present(s) when is_binary(s) and byte_size(s) > 0

  @typedoc "Worker-shaped args. All three keys required, all non-empty binaries."
  @type args :: %{
          required(:incident_report_id) => binary(),
          required(:business_owner_email) => String.t(),
          required(:business_name) => String.t()
        }

  @doc """
  Sends the incident-report email for the given args map.

  Returns `:ok` on success or `{:error, reason}` when the report row cannot be
  loaded or the notifier rejects the email.
  """
  @spec execute(args()) :: :ok | {:error, term()}
  def execute(%{incident_report_id: id, business_owner_email: owner_email, business_name: business_name})
      when is_present(id) and is_present(owner_email) and is_present(business_name) do
    with {:ok, report} <- fetch_report(id) do
      program_label = resolve_program_label(report)
      signed_url = maybe_sign_photo(report, id)

      send_email(
        %{owner_email: owner_email, business_name: business_name},
        report,
        program_label,
        signed_url
      )
    end
  end

  defp fetch_report(id) do
    case Provider.get_incident_report(id) do
      {:ok, %IncidentReport{} = report} -> {:ok, report}
      {:error, :not_found} -> {:error, :incident_report_not_found}
    end
  end

  defp resolve_program_label(%IncidentReport{program_id: pid}) when is_binary(pid) do
    case Programs.get_provider_program(pid) do
      {:ok, %{name: name}} when is_binary(name) and byte_size(name) > 0 ->
        name

      {:error, :not_found} ->
        Logger.warning("[NotifyIncidentReported] Program not found, using fallback label",
          program_id: pid
        )

        @program_fallback_label
    end
  end

  defp resolve_program_label(%IncidentReport{}), do: @session_fallback_label

  defp maybe_sign_photo(%IncidentReport{photo_url: nil}, _id), do: nil

  defp maybe_sign_photo(%IncidentReport{photo_url: key}, id) when is_binary(key) do
    case Storage.signed_url(:private, key, @signed_url_ttl_seconds) do
      {:ok, url} ->
        url

      {:error, reason} ->
        Logger.warning("[NotifyIncidentReported] Photo signing failed, sending without photo",
          incident_report_id: id,
          reason: inspect(reason)
        )

        nil
    end
  end

  defp send_email(%{owner_email: owner_email, business_name: business_name}, report, program_label, signed_url) do
    recipient = %{email: owner_email, name: business_name}

    context = %{
      program_name: program_label,
      signed_photo_url: signed_url,
      business_name: business_name
    }

    case IncidentReportedEmailNotifier.send_incident_report(recipient, report, context) do
      {:ok, _email} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
