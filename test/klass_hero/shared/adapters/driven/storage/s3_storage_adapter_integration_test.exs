defmodule KlassHero.Shared.Adapters.Driven.Storage.S3StorageAdapterIntegrationTest do
  @moduledoc """
  Integration tests for S3StorageAdapter using MinIO.

  These tests verify the adapter works correctly against a real S3-compatible
  storage backend (MinIO running in Docker).

  ## Running These Tests

  MinIO must be running via docker-compose:

      docker compose up -d minio
      mix test test/klass_hero/shared/adapters/driven/storage/s3_storage_adapter_integration_test.exs --include minio

  ## Not a CI gate

  CI defines only a `postgres` service, so these never run there and nothing opts
  `:minio` in. That is a deliberate decision (#1267), not an oversight: coverage of
  `S3StorageAdapter` against a real S3 backend is developer-run only, and the
  adapter is therefore unverified on every PR.
  """

  use KlassHero.StorageIntegrationCase

  describe "upload/4" do
    test "uploads file to public bucket and returns URL" do
      path = "logos/test-#{System.unique_integer([:positive])}.png"
      binary = "test image content"

      assert {:ok, url} = S3StorageAdapter.upload(:public, path, binary, [])
      assert url =~ "klass-hero-test"
      assert url =~ path
    end

    test "uploads file to private bucket and returns key" do
      path = "docs/test-#{System.unique_integer([:positive])}.pdf"
      binary = "test document content"

      assert {:ok, key} = S3StorageAdapter.upload(:private, path, binary, [])
      assert key == path
    end

    test "uploads file with custom content type" do
      path = "images/test-#{System.unique_integer([:positive])}.jpg"
      binary = "fake jpeg content"

      assert {:ok, url} =
               S3StorageAdapter.upload(:public, path, binary, content_type: "image/jpeg")

      assert url =~ path
    end

    test "overwrites existing file" do
      path = "logos/overwrite-test-#{System.unique_integer([:positive])}.png"

      assert {:ok, _url1} = S3StorageAdapter.upload(:public, path, "original content", [])
      assert {:ok, _url2} = S3StorageAdapter.upload(:public, path, "updated content", [])
    end
  end

  describe "signed_url/4" do
    test "generates signed URL for private file" do
      path = "docs/test-#{System.unique_integer([:positive])}.pdf"
      S3StorageAdapter.upload(:private, path, "test content", [])

      assert {:ok, url} = S3StorageAdapter.signed_url(:private, path, 300, [])
      assert url =~ path
      assert url =~ "X-Amz-Signature"
    end

    test "generates signed URL with custom expiration" do
      path = "docs/test-#{System.unique_integer([:positive])}.pdf"
      S3StorageAdapter.upload(:private, path, "test content", [])

      # 1 hour expiration
      assert {:ok, url} = S3StorageAdapter.signed_url(:private, path, 3600, [])
      assert url =~ "X-Amz-Expires=3600"
    end
  end

  describe "delete/3" do
    test "deletes file from public bucket" do
      path = "logos/test-#{System.unique_integer([:positive])}.png"
      S3StorageAdapter.upload(:public, path, "test content", [])

      assert :ok = S3StorageAdapter.delete(:public, path, [])
    end

    test "deletes file from private bucket" do
      path = "docs/test-#{System.unique_integer([:positive])}.pdf"
      S3StorageAdapter.upload(:private, path, "test content", [])

      assert :ok = S3StorageAdapter.delete(:private, path, [])
    end

    test "returns ok when deleting non-existent file" do
      # S3 delete is idempotent - deleting non-existent file doesn't error
      path = "logos/non-existent-#{System.unique_integer([:positive])}.png"

      assert :ok = S3StorageAdapter.delete(:public, path, [])
    end
  end

  describe "round-trip verification" do
    test "uploaded file can be retrieved via signed URL" do
      path = "docs/roundtrip-#{System.unique_integer([:positive])}.txt"
      content = "This is test content for round-trip verification"

      # Upload
      assert {:ok, _key} = S3StorageAdapter.upload(:private, path, content, [])

      # Get signed URL
      assert {:ok, signed_url} = S3StorageAdapter.signed_url(:private, path, 300, [])

      # Fetch content via signed URL
      assert {:ok, %{status: 200, body: fetched_content}} = Req.get(signed_url)
      assert fetched_content == content
    end
  end
end
