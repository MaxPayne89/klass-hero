defmodule KlassHero.Messaging.NewMessageEmailNotifier do
  @moduledoc """
  Swoosh adapter telling someone they have a new message.

  Carries a link and nothing else. The message body never reaches this module —
  not because it is unavailable (the `message_sent` payload does carry
  `content`), but because an inbox notification that quotes the message would
  put private conversation text into an unencrypted mailbox and into every mail
  provider's logs. The recipient reads it in the app.
  """

  use KlassHero.Shared.Interaction

  import Swoosh.Email

  alias KlassHero.Mailer
  alias KlassHero.Shared.EmailHtml

  @from Application.compile_env!(:klass_hero, [:mailer_defaults, :from])

  @doc """
  Emails `recipient` that `conversation_id` has a new message waiting.

  `recipient` is `%{email: String.t(), name: String.t() | nil}`.
  """
  @spec send_new_message_notice(map(), String.t()) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def send_new_message_notice(recipient, conversation_id) do
    email_interaction operation: :send_new_message_notice do
      url = conversation_url(conversation_id)
      name = recipient.name || recipient.email

      email =
        new()
        |> to({name, recipient.email})
        |> from(@from)
        |> subject("You have a new message on Klass Hero")
        |> text_body(text_body(url))
        |> html_body(html_body(url))

      with {:ok, _metadata} <- Mailer.deliver(email) do
        {:ok, email}
      end
    end
  end

  # /messages/:id sits in the :authenticated live_session, so one URL shape is
  # correct for a parent, a staff member and a provider alike.
  defp conversation_url(conversation_id) do
    base = Application.get_env(:klass_hero, :app_base_url, "http://localhost:4000")

    "#{base}/messages/#{conversation_id}"
  end

  defp text_body(url) do
    """
    You have a new message waiting for you on Klass Hero.

    Read it here: #{url}

    We don't include message content in emails — open the conversation to read it.
    """
  end

  # The button repeats Enrollment's invite-email values on purpose — the two
  # should look alike. A shared `EmailHtml.button/2` waits for a third caller.
  defp html_body(url) do
    EmailHtml.wrap(~s|
      <p style="font-size: 16px;">You have a new message waiting for you on Klass Hero.</p>
      <p style="margin: 30px 0;">
        <a href="#{EmailHtml.esc(url)}"
           style="background-color: #4F46E5; color: white; padding: 12px 30px; text-decoration: none; border-radius: 6px; font-weight: 600; display: inline-block;">
          Read your message
        </a>
      </p>
      <p style="color: #666; font-size: 14px;">
        We don't include message content in emails — open the conversation to read it.
      </p>
    |)
  end
end
