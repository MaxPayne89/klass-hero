defmodule KlassHero.Shared.ReadTable do
  @moduledoc """
  Marks an Ecto schema as a **projection read table**.

      defmodule KlassHero.Provider.ProviderProgram do
        use Ecto.Schema
        use KlassHero.Shared.ReadTable

        schema "provider_programs" do
          # ...
        end
      end

  A read table is the denormalized output of a projection GenServer under
  `adapters/driven/projections/`. Four rules follow from that; `mix lint_read_tables`
  enforces the first three, and a guard test enforces the fourth:

  1. **No changeset.** The projection is the only writer, so there is no user input
     to validate at this boundary. A changeset here means something other than the
     projection is writing the table.
  2. **The schema is the DTO.** Consumers read this struct directly — no separate
     display struct, no mapper. If you are writing a `to_dto/1`, the two modules
     should be one.
  3. **It lives at the context root** (`lib/klass_hero/<context>/<name>.ex`), beside
     the entities, not inside `adapters/`.
  4. **No length caps.** Its string columns are `text`. Rule 1 is why: with no
     changeset, a `varchar(n)` cannot *reject* an over-long value — it can only crash
     the projection mid-delivery, exhaust Oban's attempts and discard the event,
     losing every field of that update (#1376). Caps belong on the write side, where a
     changeset turns them into a user-visible error. This one is enforced by
     `test/klass_hero/shared/read_table_column_types_test.exs`, not by the lint: the
     property lives in the database, and `field :url, :string` reads identically
     whether the column is `varchar(255)` or `text`.

  This `use` is the declaration the lint keys off. It is deliberately a code token
  rather than a phrase in the moduledoc: a moduledoc can be reworded by a docs pass
  without anyone noticing the gate stopped covering the file.

  Contrast with `KlassHero.Shared.Projection`, which the *writer* uses. Every read
  table has a projection; the two markers are the two ends of one pattern.

  See `.claude/rules/domain-architecture.md` (\"CQRS Read Models\") for the three
  read-side kinds and where each lives — a query-shaped struct over write tables and
  an event-maintained table with no projection are **not** read tables and must not
  carry this marker.
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      @doc false
      def __read_table__, do: true
    end
  end
end
