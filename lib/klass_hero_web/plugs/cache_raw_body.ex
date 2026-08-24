defmodule KlassHeroWeb.Plugs.CacheRawBody do
  @moduledoc """
  Caches the raw request body for webhook signature verification.

  Used as a custom body reader for Plug.Parsers.
  Stores the raw body in conn.assigns[:raw_body].
  """

  def read_body(conn, opts) do
    case read_full_body(conn, opts, []) do
      {:ok, body, conn} ->
        conn = Plug.Conn.assign(conn, :raw_body, body)
        {:ok, body, conn}

      # Plug.Parsers contracts for {:error, reason} from a body reader and turns it into
      # a 4xx. Falling through to a CaseClauseError instead would raise inside the parser
      # on the webhook path, where a client aborting mid-body is the ordinary case.
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_full_body(conn, opts, acc) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} -> {:ok, IO.iodata_to_binary([acc | [body]]), conn}
      {:more, partial, conn} -> read_full_body(conn, opts, [acc | [partial]])
      {:error, reason} -> {:error, reason}
    end
  end
end
