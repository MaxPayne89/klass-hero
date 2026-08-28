defmodule KlassHero.Participation.MalformedIdTest do
  @moduledoc """
  A client-supplied id that is not a UUID is refused, not raised on (#1478).

  Every entry point below takes its id straight from LiveView event params, so a
  rewritten `phx-value-*` reaches the lookup with arbitrary text. Against a
  `binary_id` column a bare `Repo.get/2` answers that with `Ecto.Query.CastError`,
  which kills the LiveView process and reconnects the client. The refusal a caller
  can act on is `{:error, :not_found}` — the same answer a well-formed but absent
  id already gives, and the one `session_refusal_message/1` already renders.

  Written as one table rather than fourteen tests because the failure mode is
  per-lookup, not per-function: three private fetches back all fourteen, and a
  regression in any one of them should name every entry point it reaches.
  """

  use KlassHero.DataCase, async: true

  alias KlassHero.AccountsFixtures
  alias KlassHero.Participation

  @malformed "not-a-uuid"

  test "every entry point taking a client-supplied id refuses a malformed one" do
    scope = AccountsFixtures.admin_scope_fixture()

    entry_points = [
      {"complete_session/2", fn -> Participation.complete_session(scope, @malformed) end},
      {"start_session/2", fn -> Participation.start_session(scope, @malformed) end},
      {"update_session/3", fn -> Participation.update_session(scope, @malformed, %{}) end},
      {"get_session/1", fn -> Participation.get_session(@malformed) end},
      {"get_session_with_roster/1", fn -> Participation.get_session_with_roster(@malformed) end},
      {"get_session_with_roster_enriched/1", fn -> Participation.get_session_with_roster_enriched(@malformed) end},
      {"record_check_in/3", fn -> Participation.record_check_in(scope, @malformed) end},
      {"record_check_out/3", fn -> Participation.record_check_out(scope, @malformed) end},
      {"record_absence/3", fn -> Participation.record_absence(scope, @malformed) end},
      {"correct_attendance/3", fn -> Participation.correct_attendance(scope, @malformed, %{}) end},
      {"get_participation_record/1", fn -> Participation.get_participation_record(@malformed) end},
      {"submit_session_note/2",
       fn -> Participation.submit_session_note(scope, %{participation_record_id: @malformed, content: "note"}) end},
      {"review_session_note/2",
       fn -> Participation.review_session_note(scope, %{note_id: @malformed, decision: :approve}) end},
      {"revise_session_note/2",
       fn -> Participation.revise_session_note(scope, %{note_id: @malformed, content: "note"}) end}
    ]

    failures =
      for {name, call} <- entry_points,
          result = outcome(call),
          result != {:error, :not_found} do
        "#{name} answered #{inspect(result)}"
      end

    assert failures == [],
           "expected {:error, :not_found} from every entry point, got:\n  " <> Enum.join(failures, "\n  ")
  end

  # A raise is the failure under test, so it is reported as data rather than
  # aborting the table on the first broken entry point.
  defp outcome(call) do
    call.()
  rescue
    exception -> {:raised, exception.__struct__}
  end
end
