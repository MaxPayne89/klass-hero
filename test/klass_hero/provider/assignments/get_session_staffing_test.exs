defmodule KlassHero.Provider.Assignments.GetSessionStaffingTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Provider
  alias KlassHero.Provider.Domain.ReadModels.SessionStaffing

  setup do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)
    session = insert(:program_session_schema, program_id: program.id)

    {:ok, provider: provider, program: program, session: session}
  end

  defp staff(ctx, opts \\ []) do
    insert(:staff_member_schema, [provider_id: ctx.provider.id] ++ opts)
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

  defp on_session!(ctx, staff_member) do
    {:ok, _} =
      Provider.assign_staff_to_session(%{
        provider_id: ctx.provider.id,
        session_id: ctx.session.id,
        staff_member_id: staff_member.id
      })

    staff_member
  end

  describe "get_session_staffing/1 with no overrides" do
    test "inherits the program roster", ctx do
      a = ctx |> staff() |> then(&on_program!(ctx, &1))
      b = ctx |> staff() |> then(&on_program!(ctx, &1))

      staffing = Provider.get_session_staffing(ctx.session.id)

      assert staffing.source == :program
      assert staffing.session_id == ctx.session.id
      assert staffing.program_id == ctx.program.id
      assert Enum.sort(staffing.member_ids) == Enum.sort([a.id, b.id])
      assert staffing.member_count == 2
    end

    test "inherits the program lead", ctx do
      lead = ctx |> staff() |> then(&on_program!(ctx, &1))
      {:ok, _} = Provider.set_lead_instructor(ctx.program.id, lead.id, ctx.provider.id)

      assert %SessionStaffing{lead: %{id: lead_id}} = Provider.get_session_staffing(ctx.session.id)
      assert lead_id == lead.id
    end

    test "is the empty value when nobody staffs the program either", ctx do
      staffing = Provider.get_session_staffing(ctx.session.id)

      assert staffing.source == :program
      assert staffing.member_ids == []
      assert staffing.member_count == 0
      assert staffing.lead == nil
    end

    test "skips deactivated staff, matching every other staffing read", ctx do
      active = ctx |> staff() |> then(&on_program!(ctx, &1))
      departed = ctx |> staff() |> then(&on_program!(ctx, &1))
      {:ok, _} = Provider.deactivate_staff_member(departed)

      assert %SessionStaffing{member_ids: [only]} = Provider.get_session_staffing(ctx.session.id)
      assert only == active.id
    end
  end

  describe "get_session_staffing/1 with overrides" do
    test "replaces the program roster rather than adding to it", ctx do
      _on_program_only = ctx |> staff() |> then(&on_program!(ctx, &1))
      substitute = ctx |> staff() |> then(&on_session!(ctx, &1))

      staffing = Provider.get_session_staffing(ctx.session.id)

      assert staffing.source == :override
      assert staffing.member_ids == [substitute.id]
      assert staffing.member_count == 1
    end

    test "a retired override stops counting and the session falls back to the program", ctx do
      regular = ctx |> staff() |> then(&on_program!(ctx, &1))
      substitute = ctx |> staff() |> then(&on_session!(ctx, &1))

      {:ok, _} = Provider.unassign_staff_from_session(ctx.session.id, substitute.id, ctx.provider.id)

      staffing = Provider.get_session_staffing(ctx.session.id)

      assert staffing.source == :program
      assert staffing.member_ids == [regular.id]
    end

    test "a deactivated override holder does not staff the session", ctx do
      _regular = ctx |> staff() |> then(&on_program!(ctx, &1))
      substitute = ctx |> staff() |> then(&on_session!(ctx, &1))
      {:ok, _} = Provider.deactivate_staff_member(substitute)

      staffing = Provider.get_session_staffing(ctx.session.id)

      # The override row is still there, so the session is still overridden —
      # it is simply overridden to nobody. Falling back to the program here
      # would resurrect staff the provider deliberately removed for this day.
      assert staffing.source == :override
      assert staffing.member_ids == []
    end
  end

  describe "get_session_staffing/1 lead resolution under overrides" do
    test "uses the session's own lead when one is flagged", ctx do
      program_lead = ctx |> staff() |> then(&on_program!(ctx, &1))
      {:ok, _} = Provider.set_lead_instructor(ctx.program.id, program_lead.id, ctx.provider.id)

      substitute = ctx |> staff() |> then(&on_session!(ctx, &1))
      {:ok, _} = Provider.set_session_lead_instructor(ctx.session.id, substitute.id, ctx.provider.id)

      assert %SessionStaffing{lead: %{id: lead_id}} = Provider.get_session_staffing(ctx.session.id)
      assert lead_id == substitute.id
    end

    test "inherits the program lead when they are among the override members", ctx do
      program_lead = ctx |> staff() |> then(&on_program!(ctx, &1))
      {:ok, _} = Provider.set_lead_instructor(ctx.program.id, program_lead.id, ctx.provider.id)

      # The program lead works this session too, alongside a substitute.
      on_session!(ctx, program_lead)
      _substitute = ctx |> staff() |> then(&on_session!(ctx, &1))

      assert %SessionStaffing{lead: %{id: lead_id}} = Provider.get_session_staffing(ctx.session.id)
      assert lead_id == program_lead.id
    end

    test "has no lead when the program lead is not working the session", ctx do
      program_lead = ctx |> staff() |> then(&on_program!(ctx, &1))
      {:ok, _} = Provider.set_lead_instructor(ctx.program.id, program_lead.id, ctx.provider.id)

      _substitute = ctx |> staff() |> then(&on_session!(ctx, &1))

      # Naming a lead who is not there is the worse failure — the roster would
      # claim supervision that nobody is providing.
      assert %SessionStaffing{lead: nil} = Provider.get_session_staffing(ctx.session.id)
    end
  end

  describe "list_session_staffing/1" do
    test "agrees with the per-session call for every session", ctx do
      # A different date: program_sessions is unique on (program, date, start time).
      other_session =
        insert(:program_session_schema, program_id: ctx.program.id, session_date: Date.add(Date.utc_today(), 7))

      regular = ctx |> staff() |> then(&on_program!(ctx, &1))
      substitute = ctx |> staff() |> then(&on_session!(ctx, &1))

      batch = Provider.list_session_staffing([ctx.session.id, other_session.id])

      assert batch[ctx.session.id] == Provider.get_session_staffing(ctx.session.id)
      assert batch[other_session.id] == Provider.get_session_staffing(other_session.id)

      assert batch[ctx.session.id].member_ids == [substitute.id]
      assert batch[other_session.id].member_ids == [regular.id]
    end

    test "returns an empty map for an empty list", _ctx do
      assert Provider.list_session_staffing([]) == %{}
    end

    test "omits unknown sessions rather than inventing them", ctx do
      assert Provider.list_session_staffing([Ecto.UUID.generate()]) == %{}
      assert map_size(Provider.list_session_staffing([ctx.session.id])) == 1
    end
  end

  describe "get_session_staffing_for_provider/2" do
    test "returns the staffing for an owned session", ctx do
      assert {:ok, %SessionStaffing{}} =
               Provider.get_session_staffing_for_provider(ctx.provider.id, ctx.session.id)
    end

    test "is not_found for another provider's session", ctx do
      other_provider = insert(:provider_profile_schema)

      assert {:error, :not_found} =
               Provider.get_session_staffing_for_provider(other_provider.id, ctx.session.id)
    end

    test "is not_found for an unknown session", ctx do
      assert {:error, :not_found} =
               Provider.get_session_staffing_for_provider(ctx.provider.id, Ecto.UUID.generate())
    end
  end

  describe "list_assignable_staff_for_session/2" do
    test "offers the provider's active staff who do not already override the session", ctx do
      already = ctx |> staff() |> then(&on_session!(ctx, &1))
      addable = staff(ctx)
      departed = staff(ctx)
      {:ok, _} = Provider.deactivate_staff_member(departed)

      ids = ctx.provider.id |> Provider.list_assignable_staff_for_session(ctx.session.id) |> Enum.map(& &1.id)

      assert addable.id in ids
      refute already.id in ids
      refute departed.id in ids
    end

    test "offers staff who are on the program but not yet on this session", ctx do
      # Being on the program is not being on the session — an override names
      # its own people, so a program member is still addable here.
      on_program = ctx |> staff() |> then(&on_program!(ctx, &1))
      _substitute = ctx |> staff() |> then(&on_session!(ctx, &1))

      ids = ctx.provider.id |> Provider.list_assignable_staff_for_session(ctx.session.id) |> Enum.map(& &1.id)

      assert on_program.id in ids
    end
  end
end
