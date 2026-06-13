defmodule KlassHero.Enrollment.Adapters.Driven.Notifications.InviteEmailNotifier do
  @moduledoc """
  Swoosh adapter for sending enrollment invitation emails.

  Composes HTML + plain-text emails and delivers via `KlassHero.Mailer`.
  The guardian receives a link to complete enrollment for their child.
  """

  @behaviour KlassHero.Enrollment.Domain.Ports.ForSendingInviteEmails

  import Swoosh.Email

  alias KlassHero.Mailer
  alias KlassHero.Shared.EmailHtml

  @from Application.compile_env!(:klass_hero, [:mailer_defaults, :from])

  @impl true
  def send_invite(invite, program_name, invite_url) do
    # guardian_first_name is nil for imports without names; fall back to email for a valid recipient tuple.
    recipient_name = invite.guardian_first_name || invite.guardian_email

    email =
      new()
      |> to({recipient_name, invite.guardian_email})
      |> from(@from)
      |> subject("You're invited to enroll #{invite.child_first_name} in #{program_name}")
      |> text_body(build_text_content(invite, program_name, invite_url))
      |> html_body(build_html_content(invite, program_name, invite_url))

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  defp build_text_content(invite, program_name, invite_url) do
    greeting = invite.guardian_first_name || "there"

    """
    Hi #{greeting},

    You've been invited to enroll #{invite.child_first_name} #{invite.child_last_name} in #{program_name}.

    After clicking the link below, your account will be created automatically.
    You can set a password in your account settings at any time.

    Complete your registration here:
    #{invite_url}

    If you didn't expect this email, you can safely ignore it.

    - The KlassHero Team
    """
  end

  defp build_html_content(invite, program_name, invite_url) do
    greeting = EmailHtml.esc(invite.guardian_first_name || "there")
    child_name = "#{EmailHtml.esc(invite.child_first_name)} #{EmailHtml.esc(invite.child_last_name)}"
    safe_program_name = EmailHtml.esc(program_name)
    safe_url = EmailHtml.esc(invite_url)

    inner = """
        <p>Hi #{greeting},</p>
        <p>You've been invited to enroll <strong>#{child_name}</strong> in <strong>#{safe_program_name}</strong>.</p>
        <p style="color: #666; font-size: 14px;">After clicking the link below, your account will be created automatically. You can set a password in your account settings at any time.</p>
        <div style="text-align: center; padding: 20px 0;">
          <a href="#{safe_url}" style="background-color: #4F46E5; color: white; padding: 12px 30px; text-decoration: none; border-radius: 6px; font-weight: 600; display: inline-block;">Complete Registration</a>
        </div>
        <p style="color: #666; font-size: 14px;">Or copy this link: #{safe_url}</p>
    """

    EmailHtml.wrap(inner)
  end
end
