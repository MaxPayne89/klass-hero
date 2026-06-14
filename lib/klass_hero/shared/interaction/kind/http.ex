defmodule KlassHero.Shared.Interaction.Kind.Http do
  @moduledoc """
  Interaction policy for outbound HTTP calls (Req-backed adapters).

  Adapters typically unwrap responses to a domain tuple before returning, so the
  common shapes here are `{:ok, term}` / `{:error, atom}`; the raw `Req.Response`
  clauses cover adapters that hand the response straight back.
  """

  @behaviour KlassHero.Shared.Interaction.Kind

  alias KlassHero.Shared.Interaction.Kind

  @impl true
  def classify({:ok, %Req.Response{status: status}}) when status in 200..399, do: :ok
  def classify({:ok, %Req.Response{}}), do: :error
  def classify({:ok, _}), do: :ok
  def classify(:ok), do: :ok
  def classify({:error, _}), do: :error
  def classify(_), do: :ok

  @impl true
  def normalize_error({:ok, %Req.Response{status: status}}), do: {:http_status, status}
  def normalize_error({:error, %{__exception__: true} = exception}), do: exception.__struct__
  def normalize_error({:error, {:client_error, status}}), do: {:http_status, status}
  def normalize_error({:error, reason}) when is_atom(reason), do: reason
  def normalize_error(_), do: :http_error

  @impl true
  def attributes({:ok, %Req.Response{status: status}}, opts) do
    opts |> base_attributes() |> Map.put("http.status_code", status)
  end

  def attributes(_result, opts), do: base_attributes(opts)

  @impl true
  def sanitize(input, opts), do: Kind.default_sanitize(input, opts)

  defp base_attributes(opts) do
    %{"http.service" => opts[:service], "http.operation" => opts[:operation]}
  end
end
