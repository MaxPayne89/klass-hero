defmodule KlassHeroWeb.Presenters.StaffMemberPresenter do
  @moduledoc """
  Transforms StaffMember domain models to view-ready formats.

  Four view variants exist, ordered by how much they may disclose. `to_card_view/1`
  is the **base** — the other two build on it — so anything added there lands in all
  three, which is safe only because it is the most restricted of them:

    * `to_card_view/1` — the least-privileged shape. MUST NOT include pay_rate, nor
      an internal identifier like `user_id`, nor an affordance only an owner may act
      on. Today its one caller is `ProgramStaffingPresenter`, behind
      `live_session :require_provider` — but it is the base every other variant
      inherits, so it is held to the public standard regardless of today's callers.
    * `to_admin_view/1` — business-owner-facing (Team tab). Adds pay_rate, plus
      `user_id`/`can_message?` for the Message action and `can_delete?`.
    * `to_self_view/1` — staff-member-facing (their own dashboard). Adds pay_rate.
    * `to_hero_card/1` — the genuinely public one, rendered on the unauthenticated
      program detail page. A separate shape that shares no code with the above.

  The base-is-public arrangement inverts on you the moment a field is added for a
  *privileged* surface: the natural place to type it is the base, and the base is the
  most exposed. `user_id` went in that way once (#747) and no test caught it, because
  the tests below pinned `:pay_rate` specifically rather than the key set. They now
  pin `user_id`/`can_message?` too.
  """

  use Gettext, backend: KlassHeroWeb.Gettext

  alias KlassHero.Provider.{PayRate, StaffMember}
  alias KlassHero.Shared.Money

  @spec to_card_view(StaffMember.t()) :: map()
  def to_card_view(%StaffMember{} = staff) do
    %{
      id: staff.id,
      full_name: StaffMember.full_name(staff),
      initials: StaffMember.initials(staff),
      first_name: staff.first_name,
      last_name: staff.last_name,
      role: staff.role,
      email: staff.email,
      bio: staff.bio,
      headshot_url: staff.headshot_url,
      tags: staff.tags || [],
      qualifications: staff.qualifications || [],
      active: staff.active,
      invitation_status: staff.invitation_status,
      invitation_status_label: invitation_status_label(staff.invitation_status),
      can_resend?: staff.invitation_status in [:failed, :expired]
    }
  end

  @spec to_card_view_list([StaffMember.t()]) :: [map()]
  def to_card_view_list(staff_members) when is_list(staff_members) do
    Enum.map(staff_members, &to_card_view/1)
  end

  @doc """
  Builds the prop shape consumed by `KlassHeroWeb.ProgramComponents.hero_card/1`.

  Mirrors the card view but renames `:full_name -> :name`, adds a stable DOM id,
  and leaves `:badge` nil (staff are not "Lead Instructor").
  """
  @spec to_hero_card(StaffMember.t()) :: map()
  def to_hero_card(%StaffMember{} = staff) do
    %{
      id: "hero-card-staff-#{staff.id}",
      name: StaffMember.full_name(staff),
      initials: StaffMember.initials(staff),
      headshot_url: staff.headshot_url,
      role: staff.role,
      bio: staff.bio,
      tags: staff.tags || [],
      qualifications: staff.qualifications || [],
      badge: nil
    }
  end

  @spec to_hero_card_list([StaffMember.t()]) :: [map()]
  def to_hero_card_list(staff_members) when is_list(staff_members) do
    Enum.map(staff_members, &to_hero_card/1)
  end

  @doc """
  Business-owner-facing view. Extends the card view with pay_rate + formatted rate_label.

  `erasable_ids` comes from `Provider.erasable_staff_ids/1` and decides `can_delete?`
  — whether the Team tab offers the hard delete on this row. It defaults to none,
  so a caller that does not ask about erasability never renders the action.
  """
  @spec to_admin_view(StaffMember.t(), MapSet.t(String.t())) :: map()
  def to_admin_view(%StaffMember{} = staff, erasable_ids \\ MapSet.new()) do
    staff
    |> with_pay_rate()
    |> Map.merge(%{user_id: staff.user_id, can_message?: not is_nil(staff.user_id)})
    |> Map.put(:can_delete?, MapSet.member?(erasable_ids, staff.id))
  end

  @spec to_admin_view_list([StaffMember.t()], MapSet.t(String.t())) :: [map()]
  def to_admin_view_list(staff_members, erasable_ids \\ MapSet.new()) when is_list(staff_members) do
    Enum.map(staff_members, &to_admin_view(&1, erasable_ids))
  end

  @doc """
  Staff-member's own view of themselves. Includes their own pay_rate + formatted label.
  """
  @spec to_self_view(StaffMember.t()) :: map()
  def to_self_view(%StaffMember{} = staff), do: with_pay_rate(staff)

  defp with_pay_rate(%StaffMember{} = staff) do
    staff
    |> to_card_view()
    |> Map.merge(%{pay_rate: staff.pay_rate, rate_label: rate_label(staff.pay_rate)})
  end

  defp rate_label(nil), do: nil

  defp rate_label(%PayRate{type: type, money: %Money{} = money}) do
    "#{Money.format(money)} / #{rate_suffix(type)}"
  end

  defp rate_suffix(:hourly), do: gettext("hour")
  defp rate_suffix(:per_session), do: gettext("session")

  defp invitation_status_label(nil), do: nil
  defp invitation_status_label(:pending), do: gettext("Invitation Pending")
  defp invitation_status_label(:sent), do: gettext("Invitation Sent")
  defp invitation_status_label(:failed), do: gettext("Invitation Failed")
  defp invitation_status_label(:accepted), do: gettext("Joined")
  defp invitation_status_label(:expired), do: gettext("Invitation Expired")
end
