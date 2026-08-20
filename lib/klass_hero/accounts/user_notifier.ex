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
  def deliver_login_instructions(%User{confirmed_at: nil} = user, url) do
    deliver_confirmation_instructions(user, url)
  end

  def deliver_login_instructions(user, url) do
    deliver_magic_link_instructions(user, url)
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
  Delivers a staff invitation to someone without a Klass Hero account.

  They set up an account (role `:staff` only — joining a team is not becoming a
  provider, ADR-0005) by following the accept link. `url` is the full accept-screen
  URL (passed from the web layer to avoid boundary violations).
  """
  def deliver_staff_invitation(email, %{business_name: business_name, first_name: first_name}, url) do
    deliver(email, "#{business_name} has invited you to join their team on Klass Hero", """
    Hi #{first_name},

    #{business_name} has invited you to join their team on Klass Hero as a staff member.

    Set up your account to accept:

    #{url}

    Your name is already filled in — just confirm it and choose a password, and
    you'll be part of #{business_name}'s team.

    This invitation expires in 7 days.

    By creating your account you agree to our terms of service.

    If you did not expect this invitation, you can ignore this email.
    """)
  end

  @doc """
  Delivers a staff invitation to someone who already has a Klass Hero account.

  They accept by logging into their existing account and confirming the link — no
  new registration. `url` is the full accept-screen URL (passed from the web layer
  to avoid boundary violations).
  """
  def deliver_staff_link_invitation(email, %{business_name: business_name, name: name}, url) do
    deliver(email, "#{business_name} has invited you to join their team on Klass Hero", """
    Hi #{name},

    #{business_name} has invited you to join their team on Klass Hero as a staff member.

    You already have a Klass Hero account — log in to accept and join the team:

    #{url}

    Being added as staff does not change your existing account; it simply adds this
    team to it. This invitation expires in 7 days.

    If you did not expect this invitation, you can ignore this email.
    """)
  end
end
