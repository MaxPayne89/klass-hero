defmodule KlassHero.Messaging.Adapters.Driven.Persistence.Mappers.InboundEmailMapper do
  @moduledoc """
  Maps between InboundEmailSchema (Ecto) and InboundEmail (domain model).
  """

  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.InboundEmailSchema
  alias KlassHero.Messaging.Domain.Models.InboundEmail

  @doc """
  Converts an InboundEmailSchema to a domain InboundEmail.
  """
  @spec to_domain(InboundEmailSchema.t()) :: InboundEmail.t()
  def to_domain(%InboundEmailSchema{} = schema) do
    %InboundEmail{
      id: schema.id,
      resend_id: schema.resend_id,
      from_address: schema.from_address,
      from_name: schema.from_name,
      to_addresses: schema.to_addresses,
      cc_addresses: schema.cc_addresses,
      subject: schema.subject,
      body_html: schema.body_html,
      body_text: schema.body_text,
      headers: schema.headers,
      message_id: schema.message_id,
      status: parse_status(schema.status),
      content_status: parse_content_status(schema.content_status),
      read_by_id: schema.read_by_id,
      read_at: schema.read_at,
      received_at: schema.received_at,
      inserted_at: schema.inserted_at,
      updated_at: schema.updated_at
    }
  end

  # String.to_existing_atom/1 is unsafe in async tests; pattern-match instead.
  defp parse_status("unread"), do: :unread
  defp parse_status("read"), do: :read
  defp parse_status("archived"), do: :archived

  defp parse_content_status("pending"), do: :pending
  defp parse_content_status("fetched"), do: :fetched
  defp parse_content_status("failed"), do: :failed

  @doc """
  Converts creation attributes to schema-compatible format.
  """
  @spec to_create_attrs(map()) :: map()
  def to_create_attrs(attrs) when is_map(attrs) do
    attrs
    |> Map.take([
      :resend_id,
      :from_address,
      :from_name,
      :to_addresses,
      :cc_addresses,
      :subject,
      :body_html,
      :body_text,
      :headers,
      :message_id,
      :content_status,
      :status,
      :received_at
    ])
    |> Map.put_new(:status, "unread")
    |> Map.put_new(:content_status, "pending")
  end
end
