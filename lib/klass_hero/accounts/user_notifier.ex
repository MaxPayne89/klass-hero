defmodule KlassHero.Accounts.UserNotifier do
  @moduledoc """
  Handles email notifications for user account operations.

  Delivers emails for account confirmation, magic link authentication,
  password resets, and email change confirmations using Swoosh.
  """

  import Swoosh.Email

  alias KlassHero.Accounts.User
  alias KlassHero.Mailer

  @from Application.compile_env!(:klass_hero, [:mailer_defaults, :from])

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from(@from)
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Update email instructions", """

    ==============================

    Hi #{user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  defp deliver_magic_link_instructions(user, url) do
    deliver(user.email, "Log in instructions", """

    ==============================

    Hi #{user.email},

    You can log into your account by visiting the URL below:

    #{url}

    If you didn't request this email, please ignore this.

    ==============================
    """)
  end

  defp deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirmation instructions", """

    ==============================

    Hi #{user.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ==============================
    """)
  end

  @doc """
  Delivers a staff invitation email with a registration link.

  `url` must be the full registration URL (passed from the web layer to avoid
  boundary violations).
  """
  def deliver_staff_invitation(email, %{business_name: business_name, first_name: first_name}, url) do
    deliver(email, "#{business_name} has invited you to join Klass Hero", """
    Hi #{first_name},

    #{business_name} has added you to their team on Klass Hero — and you're set up
    to start earning with your own programs too.

    You'll get a free provider account, linked to #{business_name}'s programs and
    ready for your own.

    Claim your account & get started:

    #{url}

    Here's how it works:
    1. Click the link above
    2. Your name is already filled in — just confirm it and set a password
    3. You'll have a free provider account, linked to #{business_name}'s programs

    No monthly fees. No setup costs.

    This invitation expires in 7 days.

    By claiming your account you agree to our terms of service.

    If you did not expect this invitation, you can ignore this email.
    """)
  end

  @doc """
  Delivers a notification email when an existing user is added as a staff member.

  Requires a map with `business_name`, `name`, and `dashboard_url`. URLs must be
  full URLs (passed from the web layer to avoid boundary violations).
  """
  def deliver_staff_added_notification(email, %{business_name: business_name, name: name, dashboard_url: dashboard_url}) do
    deliver(email, "#{business_name} has invited you to join Klass Hero", """
    Hi #{name},

    #{business_name} has added you to their team on Klass Hero — and you now have
    a free provider account of your own, ready for your programs.

    You're linked to #{business_name}'s programs and can start managing your own
    activities right away.

    View your staff dashboard:

    #{dashboard_url}

    By continuing to use your account you agree to our terms of service.

    If you did not expect this, please contact #{business_name} directly.
    """)
  end
end
