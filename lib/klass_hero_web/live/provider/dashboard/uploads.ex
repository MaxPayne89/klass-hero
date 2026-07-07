defmodule KlassHeroWeb.Provider.Dashboard.Uploads do
  @moduledoc """
  Generic single-file upload plumbing shared by the provider-dashboard sub-LiveViews.

  Edit (logo, verification doc), Team (headshot), and Programs (program cover, CSV)
  all consume exactly one uploaded entry and push it to `Storage`. This module owns
  that path once, defensively wrapping `consume_uploaded_entries/3` so a dead upload
  channel or a raising `Storage.upload/4` becomes an `:upload_error` value the caller
  can flash on, rather than crashing the LiveView process.
  """

  import Phoenix.LiveView, only: [consume_uploaded_entries: 3]

  alias KlassHero.Shared.Storage

  require Logger

  @doc """
  Consume the single entry for `upload_name`, upload it under
  `"<storage_prefix>/providers/<provider_id>/<safe_name>"`, and return one of:

    * `{:ok, url}` — uploaded, `url` is the public URL
    * `:no_upload` — no file was staged
    * `:upload_error` — the channel died or the upload raised
  """
  def consume_single_upload(socket, upload_name, storage_prefix, provider_id) do
    case safe_consume_uploaded_entries(socket, upload_name, fn %{path: path}, entry ->
           try do
             # sobelow_skip ["Traversal.FileModule"]
             file_binary = File.read!(path)
             safe_name = String.replace(entry.client_name, ~r/[^a-zA-Z0-9._-]/, "_")
             storage_path = "#{storage_prefix}/providers/#{provider_id}/#{safe_name}"

             Storage.upload(:public, storage_path, file_binary, content_type: entry.client_type)
           catch
             # ExAws.request can raise; dead GenServer causes :exit — both must return an error tuple.
             kind, reason ->
               Logger.error("File upload failed",
                 upload: upload_name,
                 provider_id: provider_id,
                 kind: kind,
                 error: inspect(reason)
               )

               {:error, :upload_exception}
           end
         end) do
      {:error, :upload_channel_died} -> :upload_error
      {:ok, [url]} when is_binary(url) -> {:ok, url}
      {:ok, []} -> :no_upload
      {:ok, _other} -> :upload_error
    end
  end

  @doc """
  Wrap `consume_uploaded_entries/3` so an exiting upload channel returns
  `{:error, :upload_channel_died}` instead of taking down the caller.
  """
  def safe_consume_uploaded_entries(socket, upload_name, callback) do
    {:ok, consume_uploaded_entries(socket, upload_name, callback)}
  catch
    :exit, reason ->
      Logger.warning("Upload channel process died during consume",
        upload: upload_name,
        reason: inspect(reason)
      )

      {:error, :upload_channel_died}
  end
end
