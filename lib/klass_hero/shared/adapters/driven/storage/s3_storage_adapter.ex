defmodule KlassHero.Shared.Adapters.Driven.Storage.S3StorageAdapter do
  @moduledoc """
  S3-compatible storage adapter using ExAws.

  Works with AWS S3, Tigris, MinIO, and other S3-compatible services.
  """

  @behaviour KlassHero.Shared.ForStoringFiles

  use KlassHero.Shared.Interaction

  require Logger

  @impl true
  def upload(bucket_type, path, binary, opts) do
    s3_interaction operation: :upload do
      bucket = get_bucket()
      content_type = Keyword.get(opts, :content_type, "application/octet-stream")

      # Single bucket — visibility controlled per-object via S3 ACLs.
      put_opts =
        case bucket_type do
          :public -> [content_type: content_type, acl: :public_read]
          :private -> [content_type: content_type]
        end

      ExAws.S3.put_object(bucket, path, binary, put_opts)
      |> ExAws.request(ex_aws_config())
      |> case do
        {:ok, _response} ->
          case bucket_type do
            :public -> {:ok, public_url(bucket, path)}
            :private -> {:ok, path}
          end

        {:error, reason} ->
          Logger.error("S3 upload failed",
            bucket: bucket,
            path: path,
            error: inspect(reason)
          )

          {:error, :upload_failed}
      end
    end
  end

  @impl true
  # bucket_type intentionally ignored — public files use their URL directly; signed URLs are for private files.
  def signed_url(_bucket_type, key, expires_in, _opts) do
    s3_interaction operation: :signed_url do
      bucket = get_bucket()

      # presigned_url/5 requires a map, not keyword list
      config_map = ex_aws_config() |> Map.new()

      case ExAws.S3.presigned_url(config_map, :get, bucket, key, expires_in: expires_in) do
        {:ok, url} ->
          {:ok, url}

        {:error, reason} ->
          Logger.error("S3 presigned URL generation failed",
            bucket: bucket,
            key: key,
            error: inspect(reason)
          )

          {:error, :signed_url_failed}
      end
    end
  end

  @impl true
  # Signed URLs are pure URL math — they succeed even for nonexistent files, causing broken previews.
  def file_exists?(_bucket_type, key, _opts) do
    s3_interaction operation: :file_exists do
      bucket = get_bucket()

      ExAws.S3.head_object(bucket, key)
      |> ExAws.request(ex_aws_config())
      |> case do
        {:ok, _} ->
          {:ok, true}

        {:error, {:http_error, 404, _}} ->
          {:ok, false}

        {:error, reason} ->
          Logger.error("S3 file existence check failed",
            bucket: bucket,
            key: key,
            error: inspect(reason)
          )

          {:error, :storage_unavailable}
      end
    end
  end

  @impl true
  def delete(_bucket_type, key, _opts) do
    s3_interaction operation: :delete do
      bucket = get_bucket()

      ExAws.S3.delete_object(bucket, key)
      |> ExAws.request(ex_aws_config())
      |> case do
        {:ok, _response} ->
          :ok

        {:error, reason} ->
          Logger.error("S3 delete failed",
            bucket: bucket,
            key: key,
            error: inspect(reason)
          )

          {:error, :delete_failed}
      end
    end
  end

  defp get_bucket, do: storage_config(:bucket)

  defp public_url(bucket, path) do
    case storage_config(:endpoint) do
      nil ->
        # Tigris (production default)
        "https://#{bucket}.fly.storage.tigris.dev/#{path}"

      endpoint ->
        # MinIO or custom endpoint
        "#{endpoint}/#{bucket}/#{path}"
    end
  end

  defp storage_config(key) do
    Application.get_env(:klass_hero, :storage)[key]
  end

  defp ex_aws_config do
    config = Application.get_env(:klass_hero, :storage)

    case config[:endpoint] do
      nil ->
        # Tigris: region "auto" required per Tigris docs for global bucket routing.
        [
          access_key_id: config[:access_key_id],
          secret_access_key: config[:secret_access_key],
          region: "auto",
          host: "fly.storage.tigris.dev",
          scheme: "https://"
        ]

      endpoint ->
        # MinIO or custom endpoint
        uri = URI.parse(endpoint)

        [
          access_key_id: config[:access_key_id],
          secret_access_key: config[:secret_access_key],
          region: config[:region] || "us-east-1",
          host: uri.host,
          port: uri.port,
          scheme: "#{uri.scheme}://"
        ]
    end
  end
end
