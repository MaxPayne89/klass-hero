defmodule KlassHero.Messaging.GetInboundEmail do
  @moduledoc """
  Use case for retrieving an inbound email, optionally marking it as read.
  """

  alias KlassHero.Messaging
  alias KlassHero.Messaging.InboundEmail

  @spec execute(String.t(), keyword()) :: {:ok, InboundEmail.t()} | {:error, :not_found}
  def execute(id, opts \\ []) do
    mark_read = Keyword.get(opts, :mark_read, false)
    reader_id = Keyword.get(opts, :reader_id)

    with {:ok, email} <- Messaging.get_inbound_email_by_id(id) do
      if mark_read && reader_id do
        Messaging.mark_inbound_email_read(email, reader_id)
      else
        {:ok, email}
      end
    end
  end
end
