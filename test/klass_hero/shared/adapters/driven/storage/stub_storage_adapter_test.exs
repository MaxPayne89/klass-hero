defmodule KlassHero.Shared.Adapters.Driven.Storage.StubStorageAdapterTest do
  use ExUnit.Case, async: true

  alias KlassHero.Shared.Adapters.Driven.Storage.StubStorageAdapter

  setup do
    name = :"stub_storage_#{System.unique_integer([:positive])}"
    {:ok, pid} = StubStorageAdapter.start_link(name: name)
    %{agent: pid}
  end

  describe "upload/4" do
    test "stores file and returns stub URL for public bucket", %{agent: agent} do
      result =
        StubStorageAdapter.upload(:public, "logos/test.png", "binary_data", agent: agent)

      assert {:ok, url} = result
      assert url == "stub://public/logos/test.png"
    end

    test "stores file and returns key for private bucket", %{agent: agent} do
      result =
        StubStorageAdapter.upload(:private, "docs/test.pdf", "binary_data", agent: agent)

      assert {:ok, key} = result
      assert key == "docs/test.pdf"
    end

    test "can retrieve uploaded file", %{agent: agent} do
      StubStorageAdapter.upload(:public, "logos/test.png", "binary_data", agent: agent)

      assert {:ok, "binary_data"} =
               StubStorageAdapter.get_uploaded(:public, "logos/test.png", agent: agent)
    end
  end

  describe "signed_url/3" do
    test "returns signed URL for existing file", %{agent: agent} do
      StubStorageAdapter.upload(:private, "docs/test.pdf", "binary_data", agent: agent)
      result = StubStorageAdapter.signed_url(:private, "docs/test.pdf", 300, agent: agent)

      assert {:ok, url} = result
      assert url =~ "stub://signed/docs/test.pdf"
      assert url =~ "expires=300"
    end

    test "returns error for nonexistent file", %{agent: agent} do
      result = StubStorageAdapter.signed_url(:private, "docs/missing.pdf", 300, agent: agent)

      assert {:error, :file_not_found} = result
    end
  end

  describe "delete/2" do
    test "removes file from storage", %{agent: agent} do
      StubStorageAdapter.upload(:public, "logos/test.png", "binary_data", agent: agent)

      assert :ok = StubStorageAdapter.delete(:public, "logos/test.png", agent: agent)

      assert {:error, :file_not_found} =
               StubStorageAdapter.get_uploaded(:public, "logos/test.png", agent: agent)
    end
  end

  describe "ownership" do
    test "each owner gets its own store" do
      start_supervised!({StubStorageAdapter, owner: self()})
      StubStorageAdapter.upload(:private, "docs/mine.pdf", "mine", [])

      other_owner = spawn(fn -> Process.sleep(:infinity) end)
      on_exit(fn -> Process.exit(other_owner, :kill) end)

      assert {:ok, other_store} = StubStorageAdapter.start_link(owner: other_owner)

      assert {:error, :file_not_found} =
               StubStorageAdapter.get_uploaded(:private, "docs/mine.pdf", agent: other_store)
    end

    test "resolves the owner's store from a caller in the $callers chain" do
      start_supervised!({StubStorageAdapter, owner: self()})
      StubStorageAdapter.upload(:private, "docs/owned.pdf", "bytes", [])

      task =
        Task.async(fn -> StubStorageAdapter.signed_url(:private, "docs/owned.pdf", 300, []) end)

      assert {:ok, url} = Task.await(task)
      assert url =~ "stub://signed/docs/owned.pdf"
    end

    test "raises instead of fabricating success when no owner is registered" do
      assert_raise RuntimeError, ~r/no storage owner/i, fn ->
        StubStorageAdapter.signed_url(:private, "docs/unowned.pdf", 300, [])
      end
    end

    test "refuses to be registered under the global module name" do
      assert_raise ArgumentError, ~r/per-test owner/i, fn ->
        StubStorageAdapter.start_link(name: StubStorageAdapter)
      end
    end
  end
end
