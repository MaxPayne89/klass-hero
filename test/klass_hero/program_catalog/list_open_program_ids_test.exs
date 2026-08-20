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

  describe "list_open_program_ids_for_provider/2" do
    test "omits a program belonging to another provider", %{provider: provider} do
      own = program(provider, nil)
      foreign = insert(:program_schema, provider_id: insert(:provider_profile_schema).id)

      assert ProgramCatalog.list_open_program_ids_for_provider(provider.id, [own.id, foreign.id]) ==
               MapSet.new([own.id])
    end

    test "answers the closure question exactly as the unscoped sibling", %{provider: provider} do
      open = program(provider, nil)
      in_grace = program(provider, Date.add(Date.utc_today(), -14))
      closed = program(provider, Date.add(Date.utc_today(), -15))
      ids = [open.id, in_grace.id, closed.id]

      assert ProgramCatalog.list_open_program_ids_for_provider(provider.id, ids) ==
               ProgramCatalog.list_open_program_ids(ids)
    end

    test "omits an id that resolves to no program", %{provider: provider} do
      assert ProgramCatalog.list_open_program_ids_for_provider(provider.id, [Ecto.UUID.generate()]) ==
               MapSet.new()
    end

    test "short-circuits on an empty list", %{provider: provider} do
      assert ProgramCatalog.list_open_program_ids_for_provider(provider.id, []) == MapSet.new()
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
