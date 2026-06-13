defmodule KlassHero.Messaging.Adapters.Driven.Persistence.Mappers.EmailReplyMapper do
  @moduledoc """
  Maps between EmailReplySchema (Ecto) and EmailReply (domain model).
  """

  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.EmailReplySchema
  alias KlassHero.Messaging.Domain.Models.EmailReply

  @doc """
  Converts an EmailReplySchema to a domain EmailReply.
  """
  @spec to_domain(EmailReplySchema.t()) :: EmailReply.t()
  def to_domain(%EmailReplySchema{} = schema) do
    %EmailReply{
      id: schema.id,
      inbound_email_id: schema.inbound_email_id,
      body: schema.body,
      sent_by_id: schema.sent_by_id,
      status: parse_status(schema.status),
      resend_message_id: schema.resend_message_id,
      sent_at: schema.sent_at,
      inserted_at: schema.inserted_at,
      updated_at: schema.updated_at
    }
  end

  # String.to_existing_atom/1 is unsafe in async tests; pattern-match instead.
  defp parse_status("sending"), do: :sending
  defp parse_status("sent"), do: :sent
  defp parse_status("failed"), do: :failed

  @doc """
  Converts creation attributes to schema-compatible format.
  """
  @spec to_create_attrs(map()) :: map()
  def to_create_attrs(attrs) when is_map(attrs) do
    Map.take(attrs, [:inbound_email_id, :body, :sent_by_id, :status, :resend_message_id, :sent_at])
  end
end
