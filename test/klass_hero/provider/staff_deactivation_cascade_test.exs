defmodule KlassHero.Provider.StaffDeactivationCascadeTest do
  @moduledoc """
  End-to-end proof that deactivating a staff member actually reaches the read
  table that names them (#1237).

  The projection tests call `project/1` directly. This one starts at
  `Provider.deactivate_staff_member/1` and lets the real machinery run: staged
  event → Oban job → consumer registry → `ProviderSessionDetails`. It is the test
  that would have caught the original gap, where deactivation wrote `active`
  and told nobody.
  """
  # async: false — swaps the :outbox adapter in application env, which every
  # other test reads (see outbox_test.exs for the same constraint).
  use KlassHero.DataCase, async: false

  import KlassHero.Factory

  alias KlassHero.Provider
  alias KlassHero.Provider.SessionDetail
  alias KlassHero.Shared.Adapters.Driven.Events.ObanOutbox

  test "deactivating a staff member clears their name from upcoming sessions" do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id, title: "Judo")
    staff = insert(:staff_member_schema, provider_id: provider.id, first_name: "Jane", last_name: "Doe")

    scheduled = insert_session_detail(provider, program, staff, :scheduled)
    completed = insert_session_detail(provider, program, staff, :completed)

    # The real outbox is swapped in around the act only. Doing it in `setup`
    # makes the fixtures above collide on providers_identity_id_index: with
    # ObanOutbox live, building a provider drives :user_registered through the
    # real handler, which creates a second profile for the same identity.
    with_real_outbox(fn ->
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _} = Provider.deactivate_staff_member(staff)

        # Nothing has consumed the event yet — the job is staged, not run.
        assert Repo.get(SessionDetail, scheduled).current_assigned_staff_name == "Jane Doe"

        Oban.drain_queue(queue: :events, with_recursion: true)
      end)
    end)

    cleared = Repo.get(SessionDetail, scheduled)
    assert is_nil(cleared.current_assigned_staff_id)
    assert is_nil(cleared.current_assigned_staff_name)

    # Historical attribution is audit trail and survives.
    assert Repo.get(SessionDetail, completed).current_assigned_staff_name == "Jane Doe"
  end

  defp with_real_outbox(fun) do
    original = Application.get_env(:klass_hero, :outbox)
    Application.put_env(:klass_hero, :outbox, module: ObanOutbox)

    try do
      fun.()
    after
      Application.put_env(:klass_hero, :outbox, original)
    end
  end

  defp insert_session_detail(provider, program, staff, status) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    session_id = Ecto.UUID.generate()

    Repo.insert!(%SessionDetail{
      session_id: session_id,
      program_id: program.id,
      program_title: program.title,
      provider_id: provider.id,
      session_date: ~D[2026-09-01],
      start_time: ~T[15:00:00],
      end_time: ~T[16:00:00],
      status: status,
      current_assigned_staff_id: staff.id,
      current_assigned_staff_name: "Jane Doe",
      inserted_at: now,
      updated_at: now
    })

    session_id
  end
end
