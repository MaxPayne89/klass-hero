defmodule KlassHeroWeb.Admin.Actions.ActivateStaffAction do
  @moduledoc """
  Backpex item action reinstating a staff member's employment link.

  Not a full undo of `DeactivateStaffAction`: lead-instructor roles cleared on
  deactivation stay cleared, and a revoked invitation is not reissued — see
  `KlassHero.Provider.Staff.reactivate_staff_member/1`.

  `StaffLive.can?/3` shows this only for a staff member who is currently inactive.
  """

  use BackpexWeb, :item_action

  alias KlassHero.Provider
  alias KlassHeroWeb.Admin.Actions.StaffEmployment

  require KlassHeroWeb.BackpexCompat

  @impl Backpex.ItemAction
  def icon(assigns, _item) do
    ~H"""
    <Backpex.HTML.CoreComponents.icon name="hero-user-plus" class="h-5 w-5 text-green-600" />
    """
  end

  @impl Backpex.ItemAction
  def label(_assigns, _item), do: "Activate"

  @impl Backpex.ItemAction
  def confirm(_assigns) do
    "This restores their employment. Any lead-instructor role they held is not " <>
      "restored, and a revoked invitation is not reissued. Are you sure?"
  end

  # See the note in DeactivateStaffAction — Backpex appends a default confirm_label/1.
  KlassHeroWeb.BackpexCompat.override :confirm_label, 1 do
    @impl Backpex.ItemAction
    def confirm_label(_assigns), do: "Activate"
  end

  @impl Backpex.ItemAction
  def handle(socket, items, _data) do
    StaffEmployment.apply_to(socket, items, &Provider.reactivate_staff_member/1,
      done: "activated",
      failed: "activate",
      log: "ActivateStaffAction"
    )
  end
end
