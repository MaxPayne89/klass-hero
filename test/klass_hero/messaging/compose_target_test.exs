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
      assert target.target_name == KlassHero.Accounts.get_user!(parent_user_id).name
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

  # The directions #747 adds, plus the two that already worked, exercised through
  # the one rule that now serves all of them. A pair absent from the table is
  # refused, so the last case here is as load-bearing as the others.
  describe "build_compose_target/3 — the provider's own people" do
    setup do
      %{provider: provider, program: program, scope: owner_scope} = provider_setup()

      colleague = staff_of(provider)
      teammate = staff_of(provider)

      %{
        provider: provider,
        program: program,
        owner_scope: owner_scope,
        colleague: colleague,
        teammate: teammate
      }
    end

    test "the owner may write to a staff member, with no programme in sight", ctx do
      assert {:ok, %ComposeTarget{} = target} =
               Messaging.build_compose_target(ctx.owner_scope, ctx.provider.id, target_user_id: ctx.colleague.user.id)

      assert target.target_user_id == ctx.colleague.user.id
      assert target.target_name == ctx.colleague.user.name
      assert target.program_id == nil
    end

    test "a staff member may write to the business, naming no target", ctx do
      assert {:ok, %ComposeTarget{} = target} =
               Messaging.build_compose_target(ctx.colleague.scope, ctx.provider.id, [])

      assert target.target_user_id == ctx.provider.identity_id
      assert target.target_name == ctx.provider.business_name
    end

    test "two staff members may write to each other", ctx do
      assert {:ok, %ComposeTarget{} = target} =
               Messaging.build_compose_target(ctx.colleague.scope, ctx.provider.id,
                 target_user_id: ctx.teammate.user.id
               )

      assert target.target_user_id == ctx.teammate.user.id
    end

    test "a stranger may not write to a staff member", ctx do
      assert {:error, :unauthorized} =
               Messaging.build_compose_target(parent_scope(), ctx.provider.id, target_user_id: ctx.colleague.user.id)
    end

    test "another provider's staff member may not write to this team", ctx do
      other_provider = insert(:provider_profile_schema)
      outsider = staff_of(other_provider)

      assert {:error, :unauthorized} =
               Messaging.build_compose_target(outsider.scope, ctx.provider.id, target_user_id: ctx.colleague.user.id)
    end
  end

  defp staff_of(provider) do
    user = AccountsFixtures.user_fixture()
    insert(:staff_member_schema, provider_id: provider.id, user_id: user.id, active: true)

    scope = %Scope{
      user: user,
      roles: [:staff],
      parent: nil,
      provider: nil,
      staff_member: %{provider_id: provider.id}
    }

    %{user: user, scope: scope}
  end

  # The owner row and the scope's user are the same person, as `Scope.resolve_roles/1`
  # always makes them: the gate reads the relation from the database rather than
  # trusting the struct, so a scope claiming an ownership the row does not back is
  # refused.
  defp provider_setup do
    user = AccountsFixtures.user_fixture()
    provider = insert(:provider_profile_schema, identity_id: user.id)
    program = insert(:program_schema, provider_id: provider.id)

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
