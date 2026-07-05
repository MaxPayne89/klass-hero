defmodule KlassHero.Shared.ForStoringFiles do
  @moduledoc """
  Port for file storage operations.

  Uses a single bucket with per-object visibility control:
  - `:public` — files get public-read ACL, served directly via URL (logos, program images)
  - `:private` — files use default (private) ACL, require signed URLs (verification docs)
  """

  @type bucket_type :: :public | :private
  @type path :: String.t()
  @type binary_data :: binary()
  @type url :: String.t()
  @type key :: String.t()
  @type error_reason ::
          :upload_failed
          | :signed_url_failed
          | :file_not_found
          | :invalid_bucket
          | :storage_unavailable
          | :delete_failed
          | term()

  @doc """
  Upload a file to storage.

  Returns the storage key (for private bucket) or public URL (for public bucket).
  """
  @callback upload(bucket_type(), path(), binary_data(), keyword()) ::
              {:ok, url() | key()} | {:error, error_reason()}

  @doc """
  Generate a signed URL for accessing a private file.

  The URL expires after `expires_in_seconds`.
  """
  @callback signed_url(bucket_type(), key(), pos_integer(), keyword()) ::
              {:ok, url()} | {:error, error_reason()}

  @doc """
  Check if a file exists in storage.

  Returns `{:ok, true}` if the file exists, `{:ok, false}` if not,
  or `{:error, reason}` if the check cannot be performed.
  """
  @callback file_exists?(bucket_type(), key(), keyword()) ::
              {:ok, boolean()} | {:error, error_reason()}

  @doc """
  Delete a file from storage.
  """
  @callback delete(bucket_type(), key(), keyword()) :: :ok | {:error, error_reason()}
end
