defmodule KlassHero.ProgramCatalog.CursorCodec do
  @moduledoc """
  Seek-pagination cursor encode/decode for program listings.

  A cursor encodes `(inserted_at, id)` as a URL-safe base64 JSON blob, used by
  the paginated read-model listing query.
  """

  @type cursor_data :: {DateTime.t(), binary()}

  @spec encode(%{inserted_at: DateTime.t(), id: binary()}) :: binary()
  def encode(%{inserted_at: inserted_at, id: id}) do
    %{"ts" => DateTime.to_unix(inserted_at, :microsecond), "id" => id}
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end

  @spec decode(nil | binary()) :: {:ok, nil | cursor_data()} | {:error, :invalid_cursor}
  def decode(nil), do: {:ok, nil}

  def decode(cursor) when is_binary(cursor) do
    with {:ok, decoded} <- Base.url_decode64(cursor, padding: false),
         {:ok, data} <- Jason.decode(decoded),
         {:ok, datetime} <- parse_timestamp(data["ts"]),
         {:ok, uuid} <- parse_uuid(data["id"]) do
      {:ok, {datetime, uuid}}
    else
      _ -> {:error, :invalid_cursor}
    end
  end

  defp parse_timestamp(ts) when is_integer(ts) do
    case DateTime.from_unix(ts, :microsecond) do
      {:ok, datetime} -> {:ok, datetime}
      {:error, _} -> {:error, :invalid_timestamp}
    end
  end

  defp parse_timestamp(_), do: {:error, :invalid_timestamp}

  defp parse_uuid(uuid) when is_binary(uuid) do
    case Ecto.UUID.cast(uuid) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :invalid_uuid}
    end
  end

  defp parse_uuid(_), do: {:error, :invalid_uuid}
end
