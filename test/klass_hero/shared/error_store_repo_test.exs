defmodule KlassHero.Shared.ErrorStoreRepoTest do
  use KlassHero.DataCase, async: true

  alias ErrorTracker.Occurrence
  alias KlassHero.Accounts.User
  alias KlassHero.Shared.ErrorStoreRepo

  @leaky_reason Exception.message(%MatchError{term: {:error, %{"email" => "anna@example.de"}}})

  setup do
    {:ok, stacktrace} =
      ErrorTracker.Stacktrace.new([
        {KlassHero.Family, :create_child, 2, [file: "lib/klass_hero/family.ex", line: 42]}
      ])

    {:ok, error} = ErrorTracker.Error.new("Elixir.MatchError", @leaky_reason, stacktrace)

    %{error: error, stacktrace: stacktrace}
  end

  describe "insert!/2" do
    test "narrows the reason of an error on its way to the table", %{error: error} do
      inserted = ErrorStoreRepo.insert!(error, [])

      assert inserted.reason == "no match of right hand side value: [redacted]"
      refute Repo.get!(ErrorTracker.Error, inserted.id).reason =~ "anna@example.de"
    end

    test "narrows the reason of an occurrence too", ctx do
      # Both tables carry `reason`, and the occurrence is written from a changeset rather
      # than a struct — two shapes, one seam.
      error = ErrorStoreRepo.insert!(ctx.error, [])

      occurrence =
        error
        |> Ecto.build_assoc(:occurrences)
        |> Occurrence.changeset(%{
          stacktrace: ctx.stacktrace,
          context: %{},
          breadcrumbs: [],
          reason: @leaky_reason
        })
        |> ErrorStoreRepo.insert!([])

      assert occurrence.reason == "no match of right hand side value: [redacted]"
      refute Repo.get!(Occurrence, occurrence.id).reason =~ "anna@example.de"
    end

    test "leaves rows that are not the error store alone" do
      user = KlassHero.AccountsFixtures.user_fixture()

      assert ErrorStoreRepo.get!(User, user.id, []).id == user.id
    end
  end

  describe "delegation" do
    setup %{error: error} do
      %{inserted: ErrorStoreRepo.insert!(error, [])}
    end

    test "reads pass through to the application repo", %{inserted: inserted} do
      assert [%ErrorTracker.Error{}] = ErrorStoreRepo.all(ErrorTracker.Error, [])
      assert %ErrorTracker.Error{} = ErrorStoreRepo.one(ErrorTracker.Error, [])
      assert %ErrorTracker.Error{} = ErrorStoreRepo.get(ErrorTracker.Error, inserted.id, [])
      assert %ErrorTracker.Error{} = ErrorStoreRepo.get!(ErrorTracker.Error, inserted.id, [])
      assert ErrorStoreRepo.aggregate(ErrorTracker.Error, :count, []) == 1
    end

    test "writes and transactions pass through", %{inserted: inserted} do
      {:ok, resolved} =
        inserted |> Ecto.Changeset.change(status: :resolved) |> ErrorStoreRepo.update([])

      assert resolved.status == :resolved
      assert {:ok, :done} = ErrorStoreRepo.transaction(fn -> :done end, [])
      assert {1, nil} = ErrorStoreRepo.delete_all(ErrorTracker.Error, [])
    end

    test "reports the adapter, which ErrorTracker asks for to pick its SQL dialect" do
      assert ErrorStoreRepo.__adapter__() == Ecto.Adapters.Postgres
    end
  end

  describe "coverage of the dependency's dispatch table" do
    # ErrorTracker.Repo reaches the real repo through `apply(repo, action, args ++ [opts])`
    # over a fixed list. An upgrade adding one function to that list would raise
    # UndefinedFunctionError at report time — i.e. error reporting would break precisely
    # when something is already broken. This test fails at upgrade time instead.
    test "the shim exports every function the dependency dispatches" do
      source = File.read!("deps/error_tracker/lib/error_tracker/repo.ex")

      dispatched =
        for [_, action, args] <- Regex.scan(~r/dispatch\(:([a-z_]+!?), \[([^\]]*)\]/, source),
            do: {String.to_atom(action), length(String.split(args, ", ")) + 1}

      assert dispatched != []

      # `function_exported?/3` answers for *loaded* modules only, so without this it
      # reports false for every function whenever this test happens to run before the
      # siblings that call the shim — a seed-dependent failure claiming an upgrade
      # broke error reporting (reproduces on --seed 178683).
      Code.ensure_loaded!(ErrorStoreRepo)

      for {name, arity} <- dispatched do
        assert function_exported?(ErrorStoreRepo, name, arity),
               "ErrorTracker.Repo dispatches #{name}/#{arity}, which the shim does not export"
      end

      assert function_exported?(ErrorStoreRepo, :__adapter__, 0)
    end
  end
end
