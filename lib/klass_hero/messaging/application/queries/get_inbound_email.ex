defmodule KlassHero.Messaging.Application.Queries.GetInboundEmail do
  @moduledoc """
  Use case for retrieving an inbound email, optionally marking it as read.
  """

  alias KlassHero.Messaging.Domain.Models.InboundEmail

  @inbound_email_reader Application.compile_env!(:klass_hero, [
                          :messaging,
                          :for_querying_inbound_emails
                        ])
  @inbound_email_repo Application.compile_env!(:klass_hero, [
                        :messaging,
                        :for_managing_inbound_emails
                      ])

  @spec execute(String.t(), keyword()) :: {:ok, InboundEmail.t()} | {:error, :not_found}
  def execute(id, opts \\ []) do
    mark_read = Keyword.get(opts, :mark_read, false)
    reader_id = Keyword.get(opts, :reader_id)

    with {:ok, email} <- @inbound_email_reader.get_by_id(id) do
      maybe_mark_read(email, mark_read && reader_id, reader_id)
    end
  end

  defp maybe_mark_read(email, falsy, _reader_id) when falsy in [nil, false], do: {:ok, email}

  defp maybe_mark_read(email, _truthy, reader_id) do
    {:ok, marked} = InboundEmail.mark_read(email, reader_id)

    if marked.status == email.status do
      {:ok, email}
    else
      @inbound_email_repo.update_status(email.id, to_string(marked.status), %{
        read_by_id: marked.read_by_id,
        read_at: marked.read_at
      })
    end
  end
end
