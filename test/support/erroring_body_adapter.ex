defmodule KlassHero.Test.ErroringBodyAdapter do
  @moduledoc """
  Plug adapter stub whose `read_req_body/2` fails.

  Plug's own test adapter only ever produces `{:ok, _, _}` or `{:more, _, _}`, so the
  `{:error, reason}` branch of a body reader is unreachable through `Plug.Test.conn/3`.
  Swapping this into `conn.adapter` is the only way to exercise a client that aborts
  mid-body — the case `Plug.Conn.read_body/2` documents and callers routinely forget.

  Two states: `:error_now` fails immediately, `{:more_then_error, chunk}` yields one
  partial chunk and then fails, which is what covers a multi-chunk reader's recursion.
  """

  def read_req_body(:error_now, _opts), do: {:error, :timeout}
  def read_req_body({:more_then_error, chunk}, _opts), do: {:more, chunk, :error_now}
end
