defmodule KlassHero.StorageIntegrationCase do
  @moduledoc """
  Test case for storage integration tests using MinIO.

  These tests require MinIO running via docker-compose. Using this case template
  applies `@moduletag :minio`, which `test/test_helper.exs` excludes by default —
  no test needs to tag itself.

  ## Usage

      use KlassHero.StorageIntegrationCase

  That is the whole contract. The template's `setup_all` points `:storage` at
  MinIO, ensures the bucket exists, and restores the previous config once the
  module finishes — there is nothing for the test module to call.

  ## Not async-safe

  `:storage` is global application env, so a module using this template must stay
  synchronous. Never pass `async: true`.

  ## Running These Tests

      docker compose up -d minio
      mix test --include minio

  CI never opts `:minio` in; see the note in the test_helper exclude list.
  """

  use ExUnit.CaseTemplate

  alias KlassHero.Shared.Adapters.Driven.Storage.S3StorageAdapter

  @minio_config [
    adapter: S3StorageAdapter,
    bucket: "klass-hero-test",
    endpoint: "http://localhost:9000",
    access_key_id: "minioadmin",
    secret_access_key: "minioadmin"
  ]

  using do
    quote do
      alias KlassHero.Shared.Adapters.Driven.Storage.S3StorageAdapter

      @moduletag :minio
    end
  end

  # Restoring is the point: `config/test.exs` defaults `:storage` to the stub, and
  # both `Shared.Storage` and `S3StorageAdapter` resolve this key lazily at call
  # time. Leaving it pointed at MinIO turns every later test that signs or uploads
  # into a live S3 call (#1276).
  setup_all do
    previous = Application.get_env(:klass_hero, :storage)
    Application.put_env(:klass_hero, :storage, @minio_config)
    on_exit(fn -> Application.put_env(:klass_hero, :storage, previous) end)

    ensure_bucket()
  end

  # `docker compose up -d minio` starts MinIO without the compose file's
  # `createbuckets` service, so the bucket is not guaranteed to exist.
  defp ensure_bucket do
    ex_aws_config = [
      access_key_id: @minio_config[:access_key_id],
      secret_access_key: @minio_config[:secret_access_key],
      host: "localhost",
      port: 9000,
      scheme: "http://"
    ]

    # Result deliberately ignored: creating a bucket that already exists is an
    # error (409 on MinIO), and re-running the suite must not fail on that.
    @minio_config[:bucket]
    |> ExAws.S3.put_bucket("us-east-1")
    |> ExAws.request(ex_aws_config)

    :ok
  end
end
