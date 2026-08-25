defmodule KlassHero.Shared.StorageTest do
  use ExUnit.Case, async: true

  alias KlassHero.Shared.Adapters.Driven.Storage.StubStorageAdapter
  alias KlassHero.Shared.Storage

  doctest Storage

  # Trigger: each test needs an isolated Agent instance for the stub adapter
  # Why: async tests would conflict if sharing a single global Agent
  # Outcome: each test gets its own Agent PID via a unique name
  setup do
    # Generate a unique name for this test's Agent to enable async tests
    agent_name = :"storage_test_#{System.unique_integer([:positive])}"
    {:ok, _pid} = StubStorageAdapter.start_link(name: agent_name)
    %{agent: agent_name}
  end

  describe "upload/4" do
    test "delegates to configured adapter", %{agent: agent} do
      result =
        Storage.upload(:public, "logos/test.png", "binary",
          adapter: StubStorageAdapter,
          agent: agent
        )

      assert {:ok, "stub://public/logos/test.png"} = result
    end
  end

  describe "signed_url/4" do
    test "delegates to configured adapter", %{agent: agent} do
      Storage.upload(:private, "docs/test.pdf", "binary",
        adapter: StubStorageAdapter,
        agent: agent
      )

      result =
        Storage.signed_url(:private, "docs/test.pdf", 300,
          adapter: StubStorageAdapter,
          agent: agent
        )

      assert {:ok, url} = result
      assert url =~ "stub://signed/"
    end
  end

  describe "delete/3" do
    test "delegates to configured adapter", %{agent: agent} do
      Storage.upload(:public, "logos/test.png", "binary",
        adapter: StubStorageAdapter,
        agent: agent
      )

      assert :ok =
               Storage.delete(:public, "logos/test.png",
                 adapter: StubStorageAdapter,
                 agent: agent
               )
    end
  end

  describe "build_timestamped_path/4" do
    test "prefixes with the bucket prefix and owner id" do
      path = Storage.build_timestamped_path("incident-reports/providers", "abc-123", "photo.jpg")

      assert path =~ ~r{^incident-reports/providers/abc-123/\d+_photo\.jpg$}
    end

    test "sanitizes special characters in the filename" do
      path =
        Storage.build_timestamped_path(
          "incident-reports/providers",
          "abc-123",
          "Photo (1).JPG"
        )

      assert path =~ ~r{^incident-reports/providers/abc-123/\d+_Photo__1_\.JPG$}
    end

    test "falls back to the default filename when filename is nil" do
      path =
        Storage.build_timestamped_path(
          "verification-docs/providers",
          "abc-123",
          nil,
          "document.pdf"
        )

      assert path =~ ~r{^verification-docs/providers/abc-123/\d+_document\.pdf$}
    end

    test "uses a generic 'file' default when no default is provided" do
      path = Storage.build_timestamped_path("prefix", "owner", nil)

      assert path =~ ~r{^prefix/owner/\d+_file$}
    end

    test "embeds the current millisecond timestamp" do
      before = System.system_time(:millisecond)
      path = Storage.build_timestamped_path("p", "o", "f.txt")
      [_, ts_str] = Regex.run(~r{/(\d+)_f\.txt$}, path)
      ts = String.to_integer(ts_str)

      assert ts >= before
      assert ts <= System.system_time(:millisecond)
    end
  end
end
