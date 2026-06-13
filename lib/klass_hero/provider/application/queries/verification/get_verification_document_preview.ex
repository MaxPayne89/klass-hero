defmodule KlassHero.Provider.Application.Queries.Verification.GetVerificationDocumentPreview do
  @moduledoc """
  Use case for retrieving a verification document with a verified preview URL.

  Unlike raw `signed_url/3` (which is just URL math and succeeds even for missing files),
  this use case checks that the file actually exists in storage before generating a
  signed URL. This prevents rendering broken `<img>` / `<iframe>` previews that fetch
  S3 XML error responses.

  Returns:
  - `signed_url` — a working signed URL, or `nil` if the file is missing/inaccessible
  - `preview_type` — `:image`, `:pdf`, or `:other` for template rendering decisions
  """

  alias KlassHero.Shared.Storage

  require Logger

  @repository Application.compile_env!(:klass_hero, [
                :provider,
                :for_querying_verification_documents
              ])

  @doc """
  Retrieves a verification document with a verified preview URL.

  ## Parameters

  - `document_id` - ID of the verification document

  ## Returns

  - `{:ok, %{document: ..., provider_business_name: ..., signed_url: ..., preview_type: ...}}`
  - `{:error, :not_found}` if document doesn't exist
  """
  def execute(document_id) do
    with {:ok, result} <- @repository.get_for_admin_review(document_id) do
      signed_url = generate_verified_url(result.document.file_url)
      preview_type = file_preview_type(result.document.original_filename)

      {:ok,
       %{
         document: result.document,
         provider_business_name: result.provider_business_name,
         signed_url: signed_url,
         preview_type: preview_type
       }}
    end
  end

  # Checks file existence before generating: signed_url/3 succeeds even for missing files (URL math only).
  defp generate_verified_url(file_url) when is_binary(file_url) do
    with {:ok, true} <- Storage.file_exists?(:private, file_url),
         {:ok, url} <- Storage.signed_url(:private, file_url, 900) do
      url
    else
      {:ok, false} ->
        Logger.warning("[GetVerificationDocumentPreview] File not found in storage: #{file_url}")

        nil

      {:error, reason} ->
        Logger.error(
          "[GetVerificationDocumentPreview] Failed to generate preview URL for #{file_url}: #{inspect(reason)}"
        )

        nil
    end
  end

  defp generate_verified_url(_), do: nil

  defp file_preview_type(filename) when is_binary(filename) do
    ext = filename |> String.downcase() |> Path.extname()

    case ext do
      ext when ext in ~w(.jpg .jpeg .png .gif .webp) -> :image
      ".pdf" -> :pdf
      _ -> :other
    end
  end

  defp file_preview_type(_), do: :other
end
