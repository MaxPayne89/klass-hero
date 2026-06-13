defmodule KlassHero.Shared.Storage do
  @moduledoc """
  Public API for file storage operations.

  Delegates to the configured storage adapter (S3 in prod, Stub in tests).

  ## Bucket Types

  - `:public` - files accessible via direct URL (logos, program images)
  - `:private` - files require signed URLs with expiration (verification docs)

  ## Usage

      # Upload a logo
      {:ok, url} = Storage.upload(:public, "logos/providers/123/logo.png", binary)

      # Upload a verification document
      {:ok, key} = Storage.upload(:private, "verification-docs/providers/123/doc.pdf", binary)

      # Get signed URL for private file (5 min expiry)
      {:ok, signed_url} = Storage.signed_url(:private, key, 300)

      # Delete a file
      :ok = Storage.delete(:public, "logos/providers/123/logo.png")
  """

  alias KlassHero.Shared.Domain.Ports.ForStoringFiles

  @doc """
  Upload a file to storage.

  Returns public URL for `:public` bucket, storage key for `:private` bucket.
  """
  @spec upload(ForStoringFiles.bucket_type(), String.t(), binary(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def upload(bucket_type, path, binary, opts \\ []) do
    adapter(opts).upload(bucket_type, path, binary, opts)
  end

  @doc """
  Generate a signed URL for a private file.

  The URL expires after `expires_in_seconds`.
  """
  @spec signed_url(ForStoringFiles.bucket_type(), String.t(), pos_integer(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def signed_url(bucket_type, key, expires_in_seconds, opts \\ []) do
    adapter(opts).signed_url(bucket_type, key, expires_in_seconds, opts)
  end

  @doc """
  Check if a file exists in storage.
  """
  @spec file_exists?(ForStoringFiles.bucket_type(), String.t(), keyword()) ::
          {:ok, boolean()} | {:error, term()}
  def file_exists?(bucket_type, key, opts \\ []) do
    adapter(opts).file_exists?(bucket_type, key, opts)
  end

  @doc """
  Delete a file from storage.
  """
  @spec delete(ForStoringFiles.bucket_type(), String.t(), keyword()) :: :ok | {:error, term()}
  def delete(bucket_type, key, opts \\ []) do
    adapter(opts).delete(bucket_type, key, opts)
  end

  @doc """
  Build a timestamped, sanitized object storage path.

  Used by upload commands to derive a stable, collision-resistant key from
  a per-owner prefix and a (possibly user-supplied) filename. The filename
  is sanitized by replacing every character outside `[a-zA-Z0-9._-]` with
  an underscore, and a millisecond timestamp is prepended to avoid
  collisions when the same name is uploaded twice.

  When `filename` is `nil`, `default_filename` is used instead.

  ## Examples

      iex> path = KlassHero.Shared.Storage.build_timestamped_path(
      ...>   "incident-reports/providers",
      ...>   "abc-123",
      ...>   "Photo (1).JPG"
      ...> )
      iex> path =~ ~r{^incident-reports/providers/abc-123/\\d+_Photo__1_\\.JPG$}
      true

      iex> path = KlassHero.Shared.Storage.build_timestamped_path(
      ...>   "verification-docs/providers",
      ...>   "abc-123",
      ...>   nil,
      ...>   "doc.pdf"
      ...> )
      iex> path =~ ~r{^verification-docs/providers/abc-123/\\d+_doc\\.pdf$}
      true
  """
  @spec build_timestamped_path(String.t(), String.t(), String.t() | nil, String.t()) :: String.t()
  def build_timestamped_path(prefix, owner_id, filename, default_filename \\ "file") do
    safe_name = String.replace(filename || default_filename, ~r/[^a-zA-Z0-9._-]/, "_")
    timestamp = System.system_time(:millisecond)
    "#{prefix}/#{owner_id}/#{timestamp}_#{safe_name}"
  end

  defp adapter(opts) do
    Keyword.get_lazy(opts, :adapter, fn ->
      Application.get_env(:klass_hero, :storage)[:adapter]
    end)
  end
end
