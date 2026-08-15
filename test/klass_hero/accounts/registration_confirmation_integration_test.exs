defmodule KlassHero.Accounts.RegistrationProfileCreationIntegrationTest do
  @moduledoc """
  Integration test verifying the full registration → profile creation flow.

  Registering stages `user_registered` in the same transaction as the user row.
  The delivery job then invokes Family's and Provider's handlers directly, so the
  profiles appear when that job runs — not whenever a GenServer's mailbox is
  drained.

  That removes two things this test used to need: a swap to the real PubSub
  publisher, and `Sandbox.allow` grants for the subscriber processes. The job runs
  in the test process, on the test's own connection.
  """

  use KlassHero.DataCase, async: false

  alias KlassHero.Accounts
  alias KlassHero.Family
  alias KlassHero.Provider
  alias KlassHero.Shared.Adapters.Driven.Events.ObanOutbox

  setup do
    original_outbox = Application.get_env(:klass_hero, :outbox)
    Application.put_env(:klass_hero, :outbox, module: ObanOutbox)
    on_exit(fn -> Application.put_env(:klass_hero, :outbox, original_outbox) end)

    :ok
  end

  # Manual mode, then drain: `testing: :inline` would run the delivery job at insert,
  # inside the registration's own transaction. Production runs it after the commit.
  defp register_and_deliver(attrs) do
    {:ok, user} = Oban.Testing.with_testing_mode(:manual, fn -> Accounts.register_user(attrs) end)
    Oban.drain_queue(queue: :events, with_recursion: true)
    user
  end

  describe "provider registration → profile creation" do
    test "provider profile exists after registration" do
      user =
        register_and_deliver(%{
          "name" => "Test Provider",
          "email" => "provider-#{System.unique_integer([:positive])}@example.com",
          "intended_roles" => ["provider"]
        })

      assert Provider.has_provider_profile?(user.id)
      assert {:ok, _profile} = Provider.get_provider_by_identity(user.id)
    end

    test "parent profile exists after registration" do
      user =
        register_and_deliver(%{
          "name" => "Test Parent",
          "email" => "parent-#{System.unique_integer([:positive])}@example.com",
          "intended_roles" => ["parent"]
        })

      assert Family.has_parent_profile?(user.id)

      assert {:ok, _profile} = Family.get_parent_by_identity(user.id)
    end

    test "both profiles exist for dual-role registration" do
      user =
        register_and_deliver(%{
          "name" => "Dual Role User",
          "email" => "dual-#{System.unique_integer([:positive])}@example.com",
          "intended_roles" => ["parent", "provider"]
        })

      assert Family.has_parent_profile?(user.id)
      assert Provider.has_provider_profile?(user.id)

      assert {:ok, _parent} = Family.get_parent_by_identity(user.id)
      assert {:ok, _provider} = Provider.get_provider_by_identity(user.id)
    end
  end
end
