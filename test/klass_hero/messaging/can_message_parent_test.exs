defmodule KlassHero.Messaging.CanMessageParentTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Accounts.Scope
  alias KlassHero.AccountsFixtures
  alias KlassHero.Messaging
  alias KlassHero.Provider.ProviderProfile

  setup do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)

    scope = %Scope{
      user: AccountsFixtures.user_fixture(),
      roles: [:provider],
      parent: nil,
      provider: %ProviderProfile{id: provider.id, identity_id: provider.identity_id}
    }

    %{provider: provider, program: program, scope: scope}
  end

  describe "can_message_parent?/4" do
    test "true for a confirmed parent on the provider's program", ctx do
      parent_user_id = confirmed_parent_on(ctx.program)

      assert Messaging.can_message_parent?(ctx.scope, ctx.provider.id, ctx.program.id, parent_user_id)
    end

    test "false when the parent holds no confirmed enrollment", ctx do
      {_child, parent} = insert_child_with_guardian()

      refute Messaging.can_message_parent?(ctx.scope, ctx.provider.id, ctx.program.id, parent.identity_id)
    end

    test "false when the scope acts for a different provider", ctx do
      parent_user_id = confirmed_parent_on(ctx.program)
      other_provider = insert(:provider_profile_schema)

      refute Messaging.can_message_parent?(ctx.scope, other_provider.id, ctx.program.id, parent_user_id)
    end

    test "false for a scope acting for no provider at all", ctx do
      parent_user_id = confirmed_parent_on(ctx.program)
      unaffiliated = %Scope{user: AccountsFixtures.user_fixture(), parent: nil, provider: nil}

      refute Messaging.can_message_parent?(unaffiliated, ctx.provider.id, ctx.program.id, parent_user_id)
    end

    test "true for a staff member of that provider, whose scope carries no provider", ctx do
      parent_user_id = confirmed_parent_on(ctx.program)

      staff_scope = %Scope{
        user: AccountsFixtures.user_fixture(),
        roles: [:staff],
        parent: nil,
        provider: nil,
        staff_member: %{provider_id: ctx.provider.id}
      }

      assert Messaging.can_message_parent?(staff_scope, ctx.provider.id, ctx.program.id, parent_user_id)
    end

    test "false when a nil program_id reaches it", ctx do
      parent_user_id = confirmed_parent_on(ctx.program)

      refute Messaging.can_message_parent?(ctx.scope, ctx.provider.id, nil, parent_user_id)
    end
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
