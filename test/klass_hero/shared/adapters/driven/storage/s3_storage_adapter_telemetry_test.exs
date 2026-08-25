defmodule KlassHero.Shared.Adapters.Driven.Storage.S3StorageAdapterTelemetryTest do
  # async: false — the interaction telemetry handler is global, so a concurrent
  # module's interaction events would cross-talk into this test's assert_receive.
  use ExUnit.Case, async: false

  alias KlassHero.Shared.Adapters.Driven.Storage.S3StorageAdapter

  # signed_url/4 is pure HMAC URL signing (no socket), so it exercises the
  # s3_interaction envelope without MinIO. The other three S3 functions stay
  # covered by the MinIO-gated integration suite.
  setup do
    previous = Application.get_env(:klass_hero, :storage)

    Application.put_env(:klass_hero, :storage,
      adapter: S3StorageAdapter,
      bucket: "klass-hero-test",
      access_key_id: "test-access-key",
      secret_access_key: "test-secret-key",
      region: "us-east-1",
      endpoint: "http://localhost:9000"
    )

    test_pid = self()
    ref = make_ref()

    :telemetry.attach_many(
      {__MODULE__, ref},
      [
        [:klass_hero, :interaction, :start],
        [:klass_hero, :interaction, :stop],
        [:klass_hero, :interaction, :exception]
      ],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end,
      %{}
    )

    on_exit(fn ->
      :telemetry.detach({__MODULE__, ref})
      Application.put_env(:klass_hero, :storage, previous)
    end)

    :ok
  end

  describe "interaction telemetry" do
    test "signed_url/4 emits a :stop event with :s3 kind and :ok status" do
      assert {:ok, url} = S3StorageAdapter.signed_url(:private, "some/key.jpg", 3600, [])
      assert url =~ "some/key.jpg"

      assert_receive {:telemetry, [:klass_hero, :interaction, :stop], %{duration_us: _},
                      %{
                        io_kind: :s3,
                        operation: :signed_url,
                        status: :ok,
                        attributes: %{"s3.operation" => :signed_url}
                      }}
    end
  end
end
