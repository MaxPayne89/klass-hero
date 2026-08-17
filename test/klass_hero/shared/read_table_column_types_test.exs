defmodule KlassHero.Shared.ReadTableColumnTypesTest do
  @moduledoc """
  Guards the fourth read-table rule: **no length caps** (see
  `KlassHero.Shared.ReadTable`).

  A read table has no changeset — the projection is its only writer — so a
  `varchar(n)` on it can never *reject* an over-long value. It can only raise
  Postgres 22001 inside `EventDeliveryWorker`, burn all ten Oban attempts and
  discard the event, losing every field of that update (#1376).

  This runs against the database rather than the source, because that is where
  the property is true: `field :cover_image_url, :string` reads identically
  whether the column is `varchar(255)` or `text`, which is exactly why
  `mix lint_read_tables` (text-based, runs before compile in the `quality` job)
  cannot see this class.
  """

  use KlassHero.DataCase, async: true

  @text_udts ["text", "_text"]

  test "every read-table string column is text, never a capped varchar" do
    columns = read_table_string_columns()

    # Without this the test passes vacuously when the enumeration breaks — a
    # renamed marker or an empty module list would report green (#1142).
    refute columns == [], "no read-table string columns found — the enumeration is broken"

    capped =
      for {module, field, table, column, udt} <- columns, udt not in @text_udts do
        "#{inspect(module)}.#{field} -> #{table}.#{column} is #{inspect(udt)}"
      end

    assert capped == [], """
    Read-table columns carrying a length cap:

    #{Enum.join(capped, "\n")}

    A read table has no changeset, so a width cap cannot reject anything — it
    can only crash the projection mid-delivery and discard the event (#1376).
    Migrate these columns to :text.
    """
  end

  defp read_table_string_columns do
    modules = read_table_modules()
    udts = column_udts(Enum.map(modules, & &1.__schema__(:source)))

    for module <- modules,
        field <- module.__schema__(:fields),
        string_field?(module, field) do
      table = module.__schema__(:source)
      column = to_string(module.__schema__(:field_source, field))

      {module, field, table, column, Map.get(udts, {table, column})}
    end
  end

  defp read_table_modules do
    {:ok, modules} = :application.get_key(:klass_hero, :modules)

    Enum.filter(modules, fn module ->
      Code.ensure_loaded?(module) and function_exported?(module, :__read_table__, 0)
    end)
  end

  # Ecto.Enum is parameterized; Ecto.Type.type/1 unwraps it to its underlying
  # :string, so enum-backed columns are covered without a special case.
  defp string_field?(module, field) do
    type = Ecto.Type.type(module.__schema__(:type, field))
    type in [:string, {:array, :string}]
  end

  defp column_udts(tables) do
    {:ok, %{rows: rows}} =
      Repo.query(
        """
        SELECT table_name, column_name, udt_name
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = ANY($1)
        """,
        [tables]
      )

    Map.new(rows, fn [table, column, udt] -> {{table, column}, udt} end)
  end
end
