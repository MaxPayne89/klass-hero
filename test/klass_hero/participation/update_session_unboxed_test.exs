defmodule KlassHero.Participation.UpdateSessionUnboxedTest do
  @moduledoc """
  The one `update_session/3` test that runs *outside* the SQL sandbox.

  `update_session/3` rescheduling can land on a slot a sibling session already
  holds. Its `Repo.update/1` runs inside `Outbox.transact_with_events/2`, so
  turning that collision into `{:error, :duplicate_session}` rather than a raised
  `Postgrex.Error` depends on `mode: :savepoint` — Ecto only converts a constraint
  violation into a changeset error when the statement can be rolled back to a
  savepoint, and inside a transaction it cannot unless asked.

  Under the sandbox this is invisible: `Ecto.Adapters.SQL.Sandbox.Connection`
  proxies every statement and injects `mode: :savepoint` of its own accord, so the
  sandboxed test passes whether or not the production code asks for it. That is
  precisely how #1322 shipped green in the other direction.

  Consequences, all deliberate — see `KlassHero.Family.ConsentsUnboxedTest` for
  the same reasoning at length: `async: false`, no `DataCase`, fixtures built
  inside the block, and nothing rolls back so the block cleans up after itself.
  """

  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias KlassHero.Accounts.Scope
  alias KlassHero.Accounts.User
  alias KlassHero.Participation
  alias KlassHero.Participation.ProgramSession
  alias KlassHero.ProgramCatalog.Program
  alias KlassHero.Provider.ProviderProfile
  alias KlassHero.Repo

  test "a reschedule onto an occupied slot refuses instead of raising" do
    Sandbox.unboxed_run(Repo, fn ->
      # Pins the precondition: inside a transaction the sandbox would supply the
      # savepoint itself and the test would prove nothing.
      refute Repo.in_transaction?()

      {provider, program, moving, _blocker} = insert_fixtures()

      try do
        assert {:error, :duplicate_session} =
                 Participation.update_session(%Scope{provider: provider}, moving.id, %{
                   session_date: ~D[2027-03-02],
                   start_time: ~T[09:00:00],
                   end_time: ~T[10:30:00]
                 })
      after
        cleanup(provider, program)
      end
    end)
  end

  defp insert_fixtures do
    user =
      Repo.insert!(%User{
        email: "reschedule-unboxed-#{System.unique_integer([:positive])}@example.com",
        name: "Unboxed Test User"
      })

    provider =
      Repo.insert!(%ProviderProfile{
        identity_id: user.id,
        business_name: "Unboxed Provider #{System.unique_integer([:positive])}"
      })

    program =
      Repo.insert!(%Program{
        provider_id: provider.id,
        title: "Unboxed Program",
        description: "A program used only by the unboxed reschedule test",
        category: "education",
        age_range: "6-10 years",
        price: Decimal.new("0.00"),
        pricing_period: "per month"
      })

    blocker =
      Repo.insert!(%ProgramSession{
        program_id: program.id,
        session_date: ~D[2027-03-02],
        start_time: ~T[09:00:00],
        end_time: ~T[10:30:00],
        status: :scheduled
      })

    moving =
      Repo.insert!(%ProgramSession{
        program_id: program.id,
        session_date: ~D[2027-03-03],
        start_time: ~T[09:00:00],
        end_time: ~T[10:30:00],
        status: :scheduled
      })

    {provider, program, moving, blocker}
  end

  # Nothing rolls back here, so every row this test made must go — the `users` row
  # included. Leaving it behind is not a tidiness problem: `AccountsTest` asserts
  # on `Repo.update_all(User, ...)` across the whole table, so one leaked user
  # fails a test in another file with no visible connection to this one.
  #
  # FK order: sessions reference programs, programs reference providers, providers
  # reference users.
  defp cleanup(provider, program) do
    Repo.delete_all(from(s in ProgramSession, where: s.program_id == ^program.id))
    Repo.delete_all(from(p in Program, where: p.id == ^program.id))
    Repo.delete_all(from(p in ProviderProfile, where: p.id == ^provider.id))
    Repo.delete_all(from(u in User, where: u.id == ^provider.identity_id))
  end
end
