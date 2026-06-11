defmodule KlassHero.Release.DedupActiveStaffMembershipsTest do
  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures
  import KlassHero.ProviderFixtures

  alias KlassHero.Release.DedupActiveStaffMemberships

  # The dedup runs in the migration BEFORE the partial unique index exists;
  # the test DB already has the index, so duplicates can't be seeded through
  # it. Postgres DDL is transactional — dropping it here is rolled back with
  # the sandbox, restoring the index after each test.
  setup do
    Repo.query!("DROP INDEX staff_members_active_provider_user_index")
    :ok
  end

  defp insert_linked(provider_id, user_id, inserted_at) do
    staff = staff_member_fixture(%{provider_id: provider_id, user_id: user_id, active: true})

    {1, _} =
      Repo.update_all(
        from(s in "staff_members", where: s.id == type(^staff.id, :binary_id)),
        set: [inserted_at: inserted_at]
      )

    staff
  end

  defp active?(staff_id) do
    Repo.one!(from(s in "staff_members", where: s.id == type(^staff_id, :binary_id), select: s.active))
  end

  test "deactivates all but the newest active row per (provider, user)" do
    user = user_fixture()
    provider = provider_profile_fixture()

    older = insert_linked(provider.id, user.id, ~U[2026-01-01 10:00:00Z])
    middle = insert_linked(provider.id, user.id, ~U[2026-02-01 10:00:00Z])
    newest = insert_linked(provider.id, user.id, ~U[2026-03-01 10:00:00Z])

    assert {:ok, %{rows_deactivated: 2}} = DedupActiveStaffMemberships.run(Repo)

    refute active?(older.id)
    refute active?(middle.id)
    assert active?(newest.id)
  end

  test "leaves distinct providers, unlinked rows, and singletons untouched" do
    user = user_fixture()
    provider_a = provider_profile_fixture()
    provider_b = provider_profile_fixture()

    at_a = insert_linked(provider_a.id, user.id, ~U[2026-01-01 10:00:00Z])
    at_b = insert_linked(provider_b.id, user.id, ~U[2026-01-02 10:00:00Z])
    unlinked = staff_member_fixture(%{provider_id: provider_a.id, active: true})

    assert {:ok, %{rows_deactivated: 0}} = DedupActiveStaffMemberships.run(Repo)

    assert active?(at_a.id)
    assert active?(at_b.id)
    assert active?(unlinked.id)
  end

  test "is idempotent" do
    user = user_fixture()
    provider = provider_profile_fixture()
    insert_linked(provider.id, user.id, ~U[2026-01-01 10:00:00Z])
    insert_linked(provider.id, user.id, ~U[2026-02-01 10:00:00Z])

    assert {:ok, %{rows_deactivated: 1}} = DedupActiveStaffMemberships.run(Repo)
    assert {:ok, %{rows_deactivated: 0}} = DedupActiveStaffMemberships.run(Repo)
  end
end
