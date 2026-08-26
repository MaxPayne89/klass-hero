defmodule KlassHero.Messaging.AuthorizationTest do
  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures

  alias KlassHero.Accounts.Scope
  alias KlassHero.Messaging.Authorization
  alias KlassHero.Messaging.Conversation
  alias KlassHero.ProviderFixtures

  describe "authorize_admin/1" do
    test "authorizes a platform admin" do
      assert :ok = Authorization.authorize_admin(admin_scope_fixture())
    end

    test "refuses a non-admin scope" do
      assert {:error, :unauthorized} = Authorization.authorize_admin(user_scope_fixture())
    end
  end

  describe "authorize_provider_owner/1" do
    test "authorizes an owner and hands back the provider it resolved" do
      provider = ProviderFixtures.provider_profile_fixture()
      scope = %Scope{user: user_fixture(), provider: provider}

      assert {:ok, provider_id} = Authorization.authorize_provider_owner(scope)
      assert provider_id == provider.id
    end

    # The gate that separates this from `resolve_acting_provider/2`, which accepts a
    # staff scope on purpose. Accepting one here would let a staff member read their
    # coworkers' private threads with parents.
    test "refuses a staff scope of the very provider it works for" do
      provider = ProviderFixtures.provider_profile_fixture()
      user = user_fixture(intended_roles: [:staff])
      staff = ProviderFixtures.staff_member_fixture(provider_id: provider.id, user_id: user.id)

      assert {:error, :unauthorized} =
               Authorization.authorize_provider_owner(%Scope{user: user, staff_member: staff})
    end

    test "refuses a scope carrying neither profile" do
      assert {:error, :unauthorized} = Authorization.authorize_provider_owner(user_scope_fixture())
    end
  end

  # Drives the monitoring notice: a thread between two of the provider's own people
  # has no parent in it, so the standing disclosure's "reviewed by the activity
  # provider ... to keep children safe" is false there.
  describe "internal_conversation?/1" do
    setup do
      provider = ProviderFixtures.provider_profile_fixture()
      owner = KlassHero.Accounts.get_user!(provider.identity_id)

      staff_user = user_fixture(intended_roles: [:staff])
      ProviderFixtures.staff_member_fixture(provider_id: provider.id, user_id: staff_user.id)

      colleague = user_fixture(intended_roles: [:staff])
      ProviderFixtures.staff_member_fixture(provider_id: provider.id, user_id: colleague.id)

      %{provider: provider, owner: owner, staff: staff_user, colleague: colleague}
    end

    test "true for owner and staff member", ctx do
      assert Authorization.internal_conversation?(conversation(ctx.provider.id, ctx.owner.id, ctx.staff.id))
    end

    test "true for two staff members", ctx do
      assert Authorization.internal_conversation?(conversation(ctx.provider.id, ctx.staff.id, ctx.colleague.id))
    end

    test "false when either principal is an outsider", ctx do
      parent = user_fixture()

      refute Authorization.internal_conversation?(conversation(ctx.provider.id, ctx.owner.id, parent.id))

      refute Authorization.internal_conversation?(conversation(ctx.provider.id, parent.id, ctx.staff.id))
    end

    # Principals are nullable — a broadcast never has them, and #1528 defers the
    # NOT NULL until the prod backfill is confirmed. A nil must answer "not
    # internal", never reach `provider_relation/2` with a nil user id.
    test "false when a principal is missing", ctx do
      refute Authorization.internal_conversation?(conversation(ctx.provider.id, ctx.owner.id, nil))

      refute Authorization.internal_conversation?(conversation(ctx.provider.id, nil, nil))
    end

    test "false for a staff member of a different provider", ctx do
      other = ProviderFixtures.provider_profile_fixture()
      outsider = user_fixture(intended_roles: [:staff])
      ProviderFixtures.staff_member_fixture(provider_id: other.id, user_id: outsider.id)

      refute Authorization.internal_conversation?(conversation(ctx.provider.id, ctx.owner.id, outsider.id))
    end
  end

  defp conversation(provider_id, principal_a_id, principal_b_id) do
    %Conversation{
      provider_id: provider_id,
      principal_a_id: principal_a_id,
      principal_b_id: principal_b_id
    }
  end
end
