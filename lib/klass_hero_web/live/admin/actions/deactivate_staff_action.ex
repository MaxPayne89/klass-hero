defmodule KlassHeroWeb.Admin.Actions.DeactivateStaffAction do
  @moduledoc """
  Backpex item action ending a staff member's employment link.

  Replaces the editable `active` checkbox the admin form used to carry. That
  checkbox went straight to `Repo` through `StaffMember.admin_changeset/3`, so
  none of deactivation's consequences ran — see
  `KlassHero.Provider.Staff.deactivate_staff_member/1` (#1237).

  `StaffLive.can?/3` shows this only for a staff member who is currently active.
  """

  use BackpexWeb, :item_action

  alias KlassHero.Provider
  alias KlassHeroWeb.Admin.Actions.StaffEmployment

  require KlassHeroWeb.BackpexCompat

  @impl Backpex.ItemAction
  def icon(assigns, _item) do
    ~H"""
    <Backpex.HTML.CoreComponents.icon name="hero-user-minus" class="h-5 w-5 text-red-600" />
    """
  end

  @impl Backpex.ItemAction
  def label(_assigns, _item), do: "Deactivate"

  @impl Backpex.ItemAction
  def confirm(_assigns) do
    "This ends their employment: they lose any lead-instructor role and stop appearing " <>
      "on upcoming sessions. Their program assignments and messages are kept, and this " <>
      "can be undone. Are you sure?"
  end

  # Backpex's @before_compile appends a default confirm_label/1; Elixir 1.20's type
  # checker flags it as redundant. BackpexCompat re-emits ours after Backpex's.
  KlassHeroWeb.BackpexCompat.override :confirm_label, 1 do
    @impl Backpex.ItemAction
    def confirm_label(_assigns), do: "Deactivate"
  end

  @impl Backpex.ItemAction
  def handle(socket, items, _data) do
    StaffEmployment.apply_to(socket, items, &Provider.deactivate_staff_member/1,
      done: "deactivated",
      failed: "deactivate",
      log: "DeactivateStaffAction"
    )
  end
end
