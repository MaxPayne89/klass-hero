defmodule KlassHero.Provider.Application.Commands.StaffMembers.AcceptStaffInvitation do
  @moduledoc """
  Command for linking a User to a StaffMember and accepting the invitation.

  Synchronous twin of the `:staff_user_registered` handling in
  `StaffInvitationStatusHandler` — both funnel through here so the link logic
  (transition `:sent`/`:pending` → `:accepted`, set `user_id`) lives in one place.
  Used by the one-click accept flow (#967), where the link must complete before the
  redirect so `Scope.resolve_roles` resolves `:staff` immediately.

  Accepting also marks the new employment as the selected staff context
  (`last_selected_at`, #969 switcher): joining a team is a deliberate act, so the
  post-accept redirect lands on the NEW employer's dashboard even when the user
  previously selected another employment. Self-staffing (`CreateSelfStaffMember`)
  deliberately does NOT do this — founders default employer-first.

  Idempotent: re-accepting an invitation already accepted by the same user is a
  no-op success (the state machine has no `:accepted → :accepted` edge).
  """

  alias KlassHero.Provider.Domain.Models.StaffMember

  @staff_query Application.compile_env!(:klass_hero, [:provider, :for_querying_staff_members])
  @staff_repository Application.compile_env!(:klass_hero, [:provider, :for_storing_staff_members])

  @doc """
  Links `user_id` to `staff_member` and transitions the invitation to `:accepted`.

  Re-reads the StaffMember by id so the transition decides on fresh DB state, not
  a possibly-stale in-memory struct (e.g. one a LiveView captured at mount that has
  since expired or been accepted). Idempotent for the same user.
  """
  @spec execute(StaffMember.t(), String.t()) :: {:ok, StaffMember.t()} | {:error, term()}
  def execute(%StaffMember{id: id}, user_id) when is_binary(user_id) do
    with {:ok, staff} <- @staff_query.get(id) do
      accept(staff, user_id)
    end
  end

  defp accept(%StaffMember{invitation_status: :accepted, user_id: user_id} = staff, user_id) do
    {:ok, staff}
  end

  defp accept(%StaffMember{} = staff, user_id) do
    with {:ok, transitioned} <- StaffMember.transition_invitation(staff, :accepted),
         {:ok, linked} <- @staff_repository.update(%{transitioned | user_id: user_id}),
         {:ok, :selected} <- @staff_repository.touch_last_selected(user_id, linked.provider_id) do
      {:ok, linked}
    end
  end
end
