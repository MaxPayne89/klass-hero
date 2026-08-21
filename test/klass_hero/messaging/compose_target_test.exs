defmodule KlassHero.Messaging.ComposeTargetTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Accounts.Scope
  alias KlassHero.AccountsFixtures
  alias KlassHero.Family.ParentProfile
  alias KlassHero.Messaging
  alias KlassHero.Messaging.ComposeTarget
  alias KlassHero.Provider.ProviderProfile

  describe "build_compose_target/3 — provider or staff writing to a parent" do
    test "resolves the parent's name for a confirmed enrollment" do
      %{provider: provider, program: program, scope: scope} = provider_setup()
      parent_user_id = confirmed_parent_on(program)

      assert {:ok, %ComposeTarget{} = target} =
               Messaging.build_compose_target(scope, provider.id,
                 target_user_id: parent_user_id,
                 program_id: program.id
               )

      assert target.provider_id == provider.id
      assert target.target_user_id == parent_user_id
      assert target.program_id == program.id
      assert is_binary(target.target_name)
    end

    test "refuses a parent with no confirmed enrollment on the program" do
      %{provider: provider, program: program, scope: scope} = provider_setup()
      {_child, parent} = insert_child_with_guardian()

      assert {:error, :unauthorized} =
               Messaging.build_compose_target(scope, provider.id,
                 target_user_id: parent.identity_id,
                 program_id: program.id
               )
    end
  end

  describe "build_compose_target/3 — parent writing to a provider" do
    test "resolves the provider owner and business name" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)

      assert {:ok, %ComposeTarget{} = target} =
               Messaging.build_compose_target(parent_scope(), provider.id, program_id: program.id)

      assert target.target_user_id == provider.identity_id
      assert target.target_name == provider.business_name
      assert target.program_id == program.id
    end

    test "returns :not_found for an unknown provider" do
      assert {:error, :not_found} =
               Messaging.build_compose_target(parent_scope(), Ecto.UUID.generate(), [])
    end
  end

  defp provider_setup do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)
    user = AccountsFixtures.user_fixture()

    scope = %Scope{
      user: user,
      roles: [:provider],
      parent: nil,
      provider: %ProviderProfile{
        id: provider.id,
        identity_id: user.id,
        business_name: provider.business_name
      }
    }

    %{provider: provider, program: program, scope: scope}
  end

  defp parent_scope do
    user = AccountsFixtures.user_fixture()

    %Scope{
      user: user,
      roles: [:parent],
      provider: nil,
      parent: %ParentProfile{
        id: Ecto.UUID.generate(),
        identity_id: user.id,
        display_name: "Test Parent"
      }
    }
  end

  defp confirmed_parent_on(program) do
    {child, parent} = insert_child_with_guardian()

    insert(:enrollment_schema,
      program_id: program.id,
      child_id: child.id,
      parent_id: parent.id,
      status: "confirmed"
    )

    parent.identity_id
  end
end
