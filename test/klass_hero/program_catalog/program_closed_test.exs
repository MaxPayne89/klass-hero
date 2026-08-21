defmodule KlassHero.ProgramCatalog.ProgramClosedTest do
  @moduledoc """
  Whether a program has closed to its staff. Pure — no database and no config
  read: the cutoff arrives as data, so the grace window stays the shell's
  business (#1082).
  """

  use ExUnit.Case, async: true

  alias KlassHero.ProgramCatalog.Program

  @cutoff ~D[2026-08-06]

  describe "closed?/2" do
    # {end_date, closed?, description}
    @cases [
      {nil, false, "an open-ended program never closes"},
      {~D[2026-08-05], true, "ended before the cutoff"},
      {~D[2026-08-06], false, "ended on the cutoff — the grace window is inclusive"},
      {~D[2026-08-07], false, "ended after the cutoff, still inside the grace window"},
      {~D[2026-12-29], false, "still running"}
    ]

    for {end_date, expected, description} <- @cases do
      test description do
        program = %Program{end_date: unquote(Macro.escape(end_date))}

        assert Program.closed?(program, @cutoff) == unquote(expected),
               "closed?/2 disagreed for end_date #{inspect(unquote(Macro.escape(end_date)))}"
      end
    end
  end
end
