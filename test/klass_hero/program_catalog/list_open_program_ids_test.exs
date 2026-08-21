defmodule KlassHero.ProgramCatalog.ListOpenProgramIdsTest do
  @moduledoc """
  The batch closure question staff authorization asks (#1082).

  Deliberately returns the **open** ids rather than the closed ones: callers
  derive closed by set difference, so an id that does not resolve to a program at
  all lands on the closed side. Fail-closed by construction.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.ProgramCatalog

  setup do
    %{provider: insert(:provider_profile_schema)}
  end

  defp program(provider, end_date) do
    insert(:program_schema, provider_id: provider.id, end_date: end_date)
  end

  describe "list_open_program_ids/1" do
    test "keeps a program that ended inside the grace window", %{provider: provider} do
      program = program(provider, Date.add(Date.utc_today(), -1))

      assert ProgramCatalog.list_open_program_ids([program.id]) == MapSet.new([program.id])
    end

    test "drops a program that ended before the grace window", %{provider: provider} do
      program = program(provider, Date.add(Date.utc_today(), -15))

      assert ProgramCatalog.list_open_program_ids([program.id]) == MapSet.new()
    end

    test "keeps an open-ended program", %{provider: provider} do
      program = program(provider, nil)

      assert ProgramCatalog.list_open_program_ids([program.id]) == MapSet.new([program.id])
    end

    test "omits an id that resolves to no program, so callers read it as closed" do
      assert ProgramCatalog.list_open_program_ids([Ecto.UUID.generate()]) == MapSet.new()
    end

    test "asks one question of many ids", %{provider: provider} do
      open = program(provider, nil)
      closed = program(provider, Date.add(Date.utc_today(), -30))
      in_grace = program(provider, Date.add(Date.utc_today(), -14))

      assert ProgramCatalog.list_open_program_ids([open.id, closed.id, in_grace.id]) ==
               MapSet.new([open.id, in_grace.id])
    end

    test "short-circuits on an empty list" do
      assert ProgramCatalog.list_open_program_ids([]) == MapSet.new()
    end

    test "honours a configured grace window", %{provider: provider} do
      program = program(provider, Date.add(Date.utc_today(), -5))

      original = Application.get_env(:klass_hero, :program_access)
      Application.put_env(:klass_hero, :program_access, closed_after_days: 3)
      on_exit(fn -> Application.put_env(:klass_hero, :program_access, original) end)

      assert ProgramCatalog.list_open_program_ids([program.id]) == MapSet.new()
    end
  end

  describe "split_programs_by_closure/2" do
    test "puts a foreign program in NEITHER set", %{provider: provider} do
      own = program(provider, nil)
      foreign = insert(:program_schema, provider_id: insert(:provider_profile_schema).id)

      {open, closed} = ProgramCatalog.split_programs_by_closure(provider.id, [own.id, foreign.id])

      assert open == MapSet.new([own.id])
      # Not "closed" — that set is rendered back to the staff member as their
      # Completed programs, so another provider's program must not land in it.
      assert closed == MapSet.new()
    end

    test "puts an id resolving to no program in neither set", %{provider: provider} do
      {open, closed} = ProgramCatalog.split_programs_by_closure(provider.id, [Ecto.UUID.generate()])

      assert open == MapSet.new()
      assert closed == MapSet.new()
    end

    test "splits the provider's own programs on the grace window", %{provider: provider} do
      never_ends = program(provider, nil)
      in_grace = program(provider, Date.add(Date.utc_today(), -14))
      closed_one = program(provider, Date.add(Date.utc_today(), -15))

      {open, closed} =
        ProgramCatalog.split_programs_by_closure(provider.id, [never_ends.id, in_grace.id, closed_one.id])

      assert open == MapSet.new([never_ends.id, in_grace.id])
      assert closed == MapSet.new([closed_one.id])
    end

    test "agrees with the unscoped sibling on the open side", %{provider: provider} do
      ids =
        for end_date <- [nil, Date.add(Date.utc_today(), -14), Date.add(Date.utc_today(), -15)],
            do: program(provider, end_date).id

      {open, _closed} = ProgramCatalog.split_programs_by_closure(provider.id, ids)

      assert open == ProgramCatalog.list_open_program_ids(ids)
    end

    test "short-circuits on an empty list", %{provider: provider} do
      assert ProgramCatalog.split_programs_by_closure(provider.id, []) == {MapSet.new(), MapSet.new()}
    end
  end

  describe "closed?/1" do
    test "answers for a program already in hand, without a query", %{provider: provider} do
      closed = program(provider, Date.add(Date.utc_today(), -15))
      open = program(provider, Date.add(Date.utc_today(), -1))

      assert ProgramCatalog.closed?(closed)
      refute ProgramCatalog.closed?(open)
    end
  end
end
