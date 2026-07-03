defmodule KlassHero.Provider.Adapters.Driven.Notifications.IncidentReportedEmailNotifier do
  @moduledoc """
  Swoosh adapter for sending incident-report notification emails to a
  provider's business owner.

  Composes HTML + plain-text emails and delivers via `KlassHero.Mailer`.
  The adapter never calls ports — the use case resolves all display
  data and passes it as `context`.
  """

  use KlassHero.Shared.Interaction

  import Swoosh.Email

  alias KlassHero.Mailer
  alias KlassHero.Provider.IncidentReport
  alias KlassHero.Shared.EmailHtml

  @from Application.compile_env!(:klass_hero, [:mailer_defaults, :from])

  def send_incident_report(recipient, %IncidentReport{} = report, context) do
    email_interaction operation: :send_incident_report do
      recipient_name = recipient.name || recipient.email

      email =
        new()
        |> to({recipient_name, recipient.email})
        |> from(@from)
        |> subject(build_subject(report, context))
        |> text_body(build_text_content(report, context))
        |> html_body(build_html_content(report, context))

      with {:ok, _metadata} <- Mailer.deliver(email) do
        {:ok, email}
      end
    end
  end

  defp build_subject(%IncidentReport{} = report, %{program_name: program_name}) do
    "Incident reported: #{IncidentReport.category_label(report.category)} (#{IncidentReport.severity_label(report.severity)}) — #{program_name}"
  end

  defp build_text_content(%IncidentReport{} = report, context) do
    photo_line =
      case context.signed_photo_url do
        nil -> ""
        url -> "Photo: #{url} (link valid for 1 hour)\n\n"
      end

    """
    A new incident has been reported for #{context.program_name}.

    Category: #{IncidentReport.category_label(report.category)}
    Severity: #{IncidentReport.severity_label(report.severity)}
    Occurred at: #{format_datetime(report.occurred_at)}
    Report ID: #{report.id}

    Description:
    #{report.description}

    #{photo_line}- The KlassHero Team
    """
  end

  defp build_html_content(%IncidentReport{} = report, context) do
    safe_program = EmailHtml.esc(context.program_name)
    safe_category = EmailHtml.esc(IncidentReport.category_label(report.category))
    safe_severity = EmailHtml.esc(IncidentReport.severity_label(report.severity))
    safe_occurred = EmailHtml.esc(format_datetime(report.occurred_at))
    safe_description = EmailHtml.esc(report.description)
    safe_id = EmailHtml.esc(report.id)

    photo_section =
      case context.signed_photo_url do
        nil ->
          ""

        url ->
          safe_url = EmailHtml.esc(url)

          """
          <p style="margin: 16px 0;">
            <a href="#{safe_url}" style="color: #4F46E5; font-weight: 600;">View photo</a>
            <span style="color: #999; font-size: 12px;"> (link valid for 1 hour)</span>
          </p>
          """
      end

    inner = """
        <p>A new incident has been reported for <strong>#{safe_program}</strong>.</p>
        <table style="border-collapse: collapse; margin: 16px 0;">
          <tr><td style="padding: 4px 12px 4px 0; color: #666;">Category</td><td style="padding: 4px 0;"><strong>#{safe_category}</strong></td></tr>
          <tr><td style="padding: 4px 12px 4px 0; color: #666;">Severity</td><td style="padding: 4px 0;"><strong>#{safe_severity}</strong></td></tr>
          <tr><td style="padding: 4px 12px 4px 0; color: #666;">Occurred at</td><td style="padding: 4px 0;">#{safe_occurred}</td></tr>
          <tr><td style="padding: 4px 12px 4px 0; color: #666;">Report ID</td><td style="padding: 4px 0;">#{safe_id}</td></tr>
        </table>
        <p style="margin-top: 16px;"><strong>Description</strong></p>
        <p style="white-space: pre-wrap;">#{safe_description}</p>
        #{photo_section}
    """

    EmailHtml.wrap(inner,
      footer_message: "You're receiving this because an incident was reported for your program on KlassHero."
    )
  end

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
  end
end
