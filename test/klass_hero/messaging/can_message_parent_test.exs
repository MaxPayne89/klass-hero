defmodule KlassHero.Messaging.CanMessageParentTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Accounts.Scope
  alias KlassHero.Messaging

  defp provider_scope do
    provider = insert(:provider_profile_schema)
    %Scope{user: %{id: provider.identity_id}, roles: [:provider], parent: nil, provider: provider}
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

  describe "can_message_parent?/3" do
    test "true for a confirmed parent on the program when the scope may initiate" do
      program = insert(:program_schema)
      parent_user_id = confirmed_parent_on(program)

      assert Messaging.can_message_parent?(provider_scope(), program.id, parent_user_id)
    end

    test "false when the parent holds no confirmed enrollment on the program" do
      program = insert(:program_schema)
      {_child, parent} = insert_child_with_guardian()

      refute Messaging.can_message_parent?(provider_scope(), program.id, parent.identity_id)
    end

    test "false when the scope may not initiate messaging" do
      program = insert(:program_schema)
      parent_user_id = confirmed_parent_on(program)
      staff_only = %Scope{user: %{id: Ecto.UUID.generate()}, parent: nil, provider: nil}

      refute Messaging.can_message_parent?(staff_only, program.id, parent_user_id)
    end
  end
end
