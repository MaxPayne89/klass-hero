defmodule KlassHero.Provider.Projections.ProviderSessionDetailsSessionStaffTest do
  @moduledoc """
  Session-level staffing in `provider_session_details` (#782).

  Its own file rather than another describe block in
  `provider_session_details_test.exs`: every test here needs real
  `program_sessions` rows (the resolver reads sessions through Participation's
  facade), whereas that file's helpers fabricate read-table rows with invented
  `session_id`s.

  The pairing that matters is with the bootstrap tests below the live ones — the
  #1299 guard. A rule that the incremental path applies and a rebuild does not
  makes the same session read differently before and after a restart.
  """

  use KlassHero.DataCase, async: false

  import KlassHero.Factory

  alias KlassHero.Provider
  alias KlassHero.Provider.Events
  alias KlassHero.Provider.ProgramStaffAssignment
  alias KlassHero.Provider.Projections.ProviderSessionDetails
  alias KlassHero.Provider.SessionDetail
  alias KlassHero.Provider.StaffMember
  alias KlassHero.Repo
  alias KlassHero.Shared.Domain.Events.Event

  @test_server_name :test_provider_session_details_session_staff

  setup do
    start_supervised!({ProviderSessionDetails, name: @test_server_name})
    :sys.get_state(@test_server_name)

    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id, title: "Judo")
    session = insert(:program_session_schema, program_id: program.id)

    {:ok, provider: provider, program: program, session: session}
  end

  defp staff(ctx, first_name) do
    insert(:staff_member_schema, provider_id: ctx.provider.id, first_name: first_name, last_name: "Stone")
  end

  defp on_program!(ctx, staff_member) do
    {:ok, _} =
      Provider.assign_staff_to_program(%{
        provider_id: ctx.provider.id,
        program_id: ctx.program.id,
        staff_member_id: staff_member.id
      })

    staff_member
  end

  # Built through the real command + the real Provider.Events constructor: this is
  # the only place a producer is paired with this consumer, and a hand-rolled
  # payload would hide drift between them (#1216).
  defp override!(ctx, staff_member) do
    {:ok, assignment} =
      Provider.assign_staff_to_session(%{
        provider_id: ctx.provider.id,
        session_id: ctx.session.id,
        staff_member_id: staff_member.id
      })

    assignment
    |> Events.staff_assigned_to_session(staff_member, ctx.program.id)
    |> ProviderSessionDetails.project()

    staff_member
  end

  # The real substitution flow. Adding someone materializes the program roster, so
  # taking the regular off is a second, separate act — and it takes both for a
  # session to be genuinely staffed by the substitute alone.
  defp substitute!(ctx, substitute, regular) do
    override!(ctx, substitute)

    {:ok, retired} = Provider.unassign_staff_from_session(ctx.session.id, regular.id, ctx.provider.id)

    retired
    |> Events.staff_unassigned_from_session(regular, ctx.program.id)
    |> ProviderSessionDetails.project()

    substitute
  end

  defp seed_session_row!(ctx) do
    ProviderSessionDetails.project(
      Event.new(:session_created, :participation, :session, ctx.session.id, %{
        session_id: ctx.session.id,
        program_id: ctx.program.id,
        session_date: ctx.session.session_date,
        start_time: ctx.session.start_time,
        end_time: ctx.session.end_time
      })
    )
  end

  defp attribution(session_id) do
    row = Repo.get(SessionDetail, session_id)
    {row.current_assigned_staff_id, row.current_assigned_staff_name}
  end

  describe "staff_assigned_to_session" do
    test "keeps naming the program's earliest active member when someone is added", ctx do
      regular = ctx |> staff("Ana") |> then(&on_program!(ctx, &1))
      seed_session_row!(ctx)
      assert attribution(ctx.session.id) == {regular.id, "Ana Stone"}

      _extra = ctx |> staff("Bea") |> then(&override!(ctx, &1))

      # Adding is additive: the program roster is copied across and Bea appended,
      # so Ana still wins on earliest-assigned. Materializing with fresh
      # timestamps would reorder the roster and rename the card for no reason the
      # provider can see.
      assert attribution(ctx.session.id) == {regular.id, "Ana Stone"}
    end

    test "attributes the session to the substitute once the regular is taken off", ctx do
      regular = ctx |> staff("Ana") |> then(&on_program!(ctx, &1))
      seed_session_row!(ctx)

      substitute = ctx |> staff("Bea") |> then(&substitute!(ctx, &1, regular))

      assert attribution(ctx.session.id) == {substitute.id, "Bea Stone"}
    end

    test "blanks the attribution when the only override holder is deactivated", ctx do
      regular = ctx |> staff("Ana") |> then(&on_program!(ctx, &1))
      seed_session_row!(ctx)

      substitute = ctx |> staff("Bea") |> then(&substitute!(ctx, &1, regular))
      {:ok, _} = Provider.deactivate_staff_member(substitute)

      substitute
      |> Events.staff_member_deactivated()
      |> ProviderSessionDetails.project()

      # Not "Ana": the session is still overridden, just overridden to nobody.
      # Falling back would resurrect staff the provider took off this day.
      assert attribution(ctx.session.id) == {nil, nil}
    end
  end

  describe "staff_unassigned_from_session" do
    test "re-attributes to whoever is left when someone is taken off", ctx do
      regular = ctx |> staff("Ana") |> then(&on_program!(ctx, &1))
      seed_session_row!(ctx)
      extra = ctx |> staff("Bea") |> then(&override!(ctx, &1))

      {:ok, retired} = Provider.unassign_staff_from_session(ctx.session.id, extra.id, ctx.provider.id)

      retired
      |> Events.staff_unassigned_from_session(extra, ctx.program.id)
      |> ProviderSessionDetails.project()

      # The session stays overridden — Ana's materialized row survives the removal —
      # and she is who it names either way.
      assert attribution(ctx.session.id) == {regular.id, "Ana Stone"}
    end
  end

  describe "program-level changes do not clobber an overridden session" do
    test "assigning someone to the program leaves the override standing", ctx do
      regular = ctx |> staff("Ana") |> then(&on_program!(ctx, &1))
      seed_session_row!(ctx)
      substitute = ctx |> staff("Bea") |> then(&substitute!(ctx, &1, regular))

      newcomer = ctx |> staff("Cal") |> then(&on_program!(ctx, &1))

      %ProgramStaffAssignment{
        provider_id: ctx.provider.id,
        program_id: ctx.program.id,
        staff_member_id: newcomer.id
      }
      |> Events.staff_assigned_to_program(newcomer)
      |> ProviderSessionDetails.project()

      # A deliberate substitution outranks a program-roster change. Without this
      # guard the program event would re-attribute every :scheduled session,
      # silently undoing the override.
      assert attribution(ctx.session.id) == {substitute.id, "Bea Stone"}
    end

    test "an un-overridden sibling session still follows the program", ctx do
      regular = ctx |> staff("Ana") |> then(&on_program!(ctx, &1))

      sibling =
        insert(:program_session_schema, program_id: ctx.program.id, session_date: Date.add(Date.utc_today(), 7))

      seed_session_row!(ctx)
      seed_session_row!(%{ctx | session: sibling})

      _substitute = ctx |> staff("Bea") |> then(&override!(ctx, &1))

      assert attribution(sibling.id) == {regular.id, "Ana Stone"}
    end
  end

  describe "bootstrap agrees with the incremental path (#1299)" do
    test "rebuild reproduces the override attribution", ctx do
      regular = ctx |> staff("Ana") |> then(&on_program!(ctx, &1))
      seed_session_row!(ctx)
      substitute = ctx |> staff("Bea") |> then(&substitute!(ctx, &1, regular))

      live = attribution(ctx.session.id)

      start_supervised!(
        Supervisor.child_spec({ProviderSessionDetails, name: :session_staff_bootstrap}, id: :session_staff_bootstrap)
      )

      :ok = ProviderSessionDetails.rebuild(:session_staff_bootstrap)

      assert attribution(ctx.session.id) == live
      assert attribution(ctx.session.id) == {substitute.id, "Bea Stone"}
    end

    test "rebuild reproduces the attribution of a materialized roster", ctx do
      # The pairing that matters most for materialization: the live path picks the
      # earliest active member in Elixir, bootstrap does it in SQL with
      # ORDER BY assigned_at ASC LIMIT 1. Copies carry the program assignment's own
      # timestamp precisely so both land on the same person.
      regular = ctx |> staff("Ana") |> then(&on_program!(ctx, &1))
      seed_session_row!(ctx)
      _extra = ctx |> staff("Bea") |> then(&override!(ctx, &1))

      live = attribution(ctx.session.id)

      start_supervised!(
        Supervisor.child_spec({ProviderSessionDetails, name: :session_staff_bootstrap_materialized},
          id: :session_staff_bootstrap_materialized
        )
      )

      :ok = ProviderSessionDetails.rebuild(:session_staff_bootstrap_materialized)

      assert attribution(ctx.session.id) == live
      assert attribution(ctx.session.id) == {regular.id, "Ana Stone"}
    end

    test "rebuild reproduces the program fallback for an un-overridden session", ctx do
      regular = ctx |> staff("Ana") |> then(&on_program!(ctx, &1))
      seed_session_row!(ctx)

      start_supervised!(
        Supervisor.child_spec({ProviderSessionDetails, name: :session_staff_bootstrap_program},
          id: :session_staff_bootstrap_program
        )
      )

      :ok = ProviderSessionDetails.rebuild(:session_staff_bootstrap_program)

      assert attribution(ctx.session.id) == {regular.id, StaffMember.full_name(regular)}
    end

    test "rebuild blanks an override whose only holder is deactivated", ctx do
      regular = ctx |> staff("Ana") |> then(&on_program!(ctx, &1))
      seed_session_row!(ctx)
      substitute = ctx |> staff("Bea") |> then(&substitute!(ctx, &1, regular))
      {:ok, _} = Provider.deactivate_staff_member(substitute)

      start_supervised!(
        Supervisor.child_spec({ProviderSessionDetails, name: :session_staff_bootstrap_deactivated},
          id: :session_staff_bootstrap_deactivated
        )
      )

      :ok = ProviderSessionDetails.rebuild(:session_staff_bootstrap_deactivated)

      assert attribution(ctx.session.id) == {nil, nil}
    end

    test "rebuild keeps a retired override out of the attribution", ctx do
      regular = ctx |> staff("Ana") |> then(&on_program!(ctx, &1))
      seed_session_row!(ctx)
      extra = ctx |> staff("Bea") |> then(&override!(ctx, &1))
      {:ok, _} = Provider.unassign_staff_from_session(ctx.session.id, extra.id, ctx.provider.id)

      start_supervised!(
        Supervisor.child_spec({ProviderSessionDetails, name: :session_staff_bootstrap_retired},
          id: :session_staff_bootstrap_retired
        )
      )

      :ok = ProviderSessionDetails.rebuild(:session_staff_bootstrap_retired)

      assert attribution(ctx.session.id) == {regular.id, "Ana Stone"}
    end
  end
end
