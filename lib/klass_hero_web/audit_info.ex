defmodule KlassHeroWeb.AuditInfo do
  @moduledoc """
  Extracts the audit trail recorded alongside a waiver signature.

  ## Only `fly-client-ip` is trusted

  The app runs behind Fly's proxy, which overwrites `fly-client-ip` at the edge. Anything a
  client sends under that name is discarded before it reaches us, so it is the one header
  here that a signer cannot forge. `x-forwarded-for` is deliberately ignored: a client can
  set it to whatever it likes, and a forged IP in a legal audit trail is worse than no IP,
  because it reads as evidence.

  When no trusted header is present the address is `nil` rather than a fallback. The proxy's
  own address (what `:peer_data` would yield) identifies nobody.

  Connect info only exists on the *connected* LiveView mount; the dead render has none, so
  `nil` is a normal input here, not an error.
  """

  alias Phoenix.LiveView.Socket

  @trusted_ip_header "fly-client-ip"

  @doc """
  Captures the audit trail from a mounting LiveView.

  Call this in `mount/3`. Connect info is unavailable on the dead render, so a disconnected
  mount yields empty values and the connected mount that follows fills them in — read the
  result from assigns at submit time rather than calling this again from an event handler,
  where connect info is no longer reachable.
  """
  @spec from_socket(Socket.t()) :: %{
          ip_address: String.t() | nil,
          user_agent: String.t() | nil
        }
  def from_socket(socket) do
    if Phoenix.LiveView.connected?(socket) do
      from_connect_info(%{
        user_agent: Phoenix.LiveView.get_connect_info(socket, :user_agent),
        x_headers: Phoenix.LiveView.get_connect_info(socket, :x_headers) || []
      })
    else
      from_connect_info(nil)
    end
  end

  @doc """
  Builds `%{ip_address: ..., user_agent: ...}` from a LiveView's connect info.
  """
  @spec from_connect_info(map() | nil) :: %{ip_address: String.t() | nil, user_agent: String.t() | nil}
  def from_connect_info(nil), do: %{ip_address: nil, user_agent: nil}

  def from_connect_info(info) when is_map(info) do
    %{
      ip_address: info |> Map.get(:x_headers, []) |> trusted_client_ip(),
      user_agent: Map.get(info, :user_agent)
    }
  end

  defp trusted_client_ip(headers) when is_list(headers) do
    Enum.find_value(headers, fn
      {name, value} -> if String.downcase(name) == @trusted_ip_header, do: value
      _other -> nil
    end)
  end

  defp trusted_client_ip(_headers), do: nil
end
