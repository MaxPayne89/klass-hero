defmodule KlassHero.Provider.Staff.ListPublicStaffTest do
  @moduledoc """
  The roster behind the public provider profile's "Meet the Heroes" section.

  "Public" is two independent gates and both must hold: the employment is live
  (`active`), and someone has actually claimed the seat (`user_id`) — so the
  page names a real person rather than a name a provider typed into an
  invitation nobody ever accepted.
  """
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.AccountsFixtures
  alias KlassHero.Provider

  # One fixture carrying every exclusion at once, so a regression in any single
  # rule shows as a diff on one id set rather than passing quietly elsewhere.
  setup do
    provider = insert(:provider_profile_schema)
    other_provider = insert(:provider_profile_schema)

    %{
      provider: provider,
      shown: claimed_staff(provider),
      unclaimed: insert(:staff_member_schema, provider_id: provider.id, user_id: nil),
      deactivated: claimed_staff(provider, active: false),
      foreign: claimed_staff(other_provider)
    }
  end

  defp claimed_staff(provider, attrs \\ []) do
    [
      provider_id: provider.id,
      user_id: AccountsFixtures.user_fixture().id,
      invitation_status: :accepted
    ]
    |> Keyword.merge(attrs)
    |> then(&insert(:staff_member_schema, &1))
  end

  describe "list_public_staff/1" do
    test "returns the provider's claimed, active staff", ctx do
      assert [%{id: id}] = Provider.list_public_staff(ctx.provider.id)
      assert id == ctx.shown.id
    end

    test "excludes every kind of staff a public page must not name", ctx do
      ids = ctx.provider.id |> Provider.list_public_staff() |> Enum.map(& &1.id)

      for {reason, excluded} <- [
            {"an invitation nobody claimed", ctx.unclaimed},
            {"an employment that ended", ctx.deactivated},
            {"another provider's staff", ctx.foreign}
          ] do
        refute excluded.id in ids, "#{reason} leaked onto the public roster"
      end
    end

    test "orders by when the employment started", ctx do
      newest = claimed_staff(ctx.provider, inserted_at: ~U[2026-06-01 09:00:00.000000Z])
      oldest = claimed_staff(ctx.provider, inserted_at: ~U[2026-01-01 09:00:00.000000Z])

      ids = ctx.provider.id |> Provider.list_public_staff() |> Enum.map(& &1.id)

      assert Enum.find_index(ids, &(&1 == oldest.id)) <
               Enum.find_index(ids, &(&1 == newest.id))
    end

    test "returns an empty list rather than raising when nobody qualifies" do
      provider = insert(:provider_profile_schema)
      insert(:staff_member_schema, provider_id: provider.id, user_id: nil)

      assert Provider.list_public_staff(provider.id) == []
    end
  end
end
