defmodule KlassHero.MessagingFixtures do
  @moduledoc """
  Test fixtures for the Messaging bounded context.
  """

  alias KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.EmailReplyRepository
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.InboundEmailRepository
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.AttachmentSchema

  def attachment_fixture(message_id, attrs \\ %{}) do
    path = "messaging/attachments/#{Ecto.UUID.generate()}/photo.jpg"

    defaults = %{
      message_id: message_id,
      file_url: "https://s3.example.com/#{path}",
      storage_path: path,
      original_filename: "test_photo.jpg",
      content_type: "image/jpeg",
      file_size_bytes: 2_400_000
    }

    {:ok, attachment} =
      defaults
      |> Map.merge(attrs)
      |> then(&AttachmentSchema.create_changeset(%AttachmentSchema{}, &1))
      |> KlassHero.Repo.insert()

    attachment
  end

  def unique_resend_id, do: "resend_#{System.unique_integer([:positive])}"

  def valid_inbound_email_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      resend_id: unique_resend_id(),
      from_address: "sender#{System.unique_integer([:positive])}@example.com",
      to_addresses: ["hello@mail.klasshero.com"],
      subject: "Test Email #{System.unique_integer([:positive])}",
      body_html: "<p>Hello</p>",
      body_text: "Hello",
      headers: [],
      message_id: "<test-#{System.unique_integer([:positive])}@example.com>",
      content_status: "fetched",
      received_at: DateTime.utc_now()
    })
  end

  def inbound_email_fixture(attrs \\ %{}) do
    {:ok, email} =
      attrs
      |> valid_inbound_email_attrs()
      |> InboundEmailRepository.create()

    email
  end

  def valid_email_reply_attrs(attrs \\ %{}) do
    inbound_email_id =
      Map.get_lazy(attrs, :inbound_email_id, fn ->
        inbound_email_fixture().id
      end)

    sent_by_id =
      Map.get_lazy(attrs, :sent_by_id, fn ->
        KlassHero.AccountsFixtures.user_fixture().id
      end)

    Enum.into(attrs, %{
      inbound_email_id: inbound_email_id,
      body: "Reply #{System.unique_integer([:positive])}",
      sent_by_id: sent_by_id
    })
  end

  def email_reply_fixture(attrs \\ %{}) do
    {:ok, reply} =
      attrs
      |> valid_email_reply_attrs()
      |> EmailReplyRepository.create()

    reply
  end
end
