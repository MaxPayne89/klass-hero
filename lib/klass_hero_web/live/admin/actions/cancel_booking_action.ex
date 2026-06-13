defmodule KlassHeroWeb.Admin.Actions.CancelBookingAction do
  @moduledoc """
  Backpex item action for cancelling bookings from the admin dashboard.

  Shows a confirmation modal with consequence warning and requires a
  cancellation reason. Delegates to the CancelEnrollmentByAdmin use case
  which enforces domain lifecycle guards and dispatches events.
  """

  use BackpexWeb, :item_action

  import Ecto.Changeset

  alias Backpex.Fields.Textarea

  require KlassHeroWeb.BackpexCompat
  require Logger

  @impl Backpex.ItemAction
  def icon(assigns, _item) do
    ~H"""
    <Backpex.HTML.CoreComponents.icon name="hero-x-circle" class="h-5 w-5 text-red-600" />
    """
  end

  @impl Backpex.ItemAction
  def label(_assigns, _item), do: "Cancel Booking"

  @impl Backpex.ItemAction
  def confirm(_assigns) do
    "This will free the reserved slot and cannot be undone. Are you sure?"
  end

  # Backpex's @before_compile appends a default confirm_label/1; Elixir 1.20 type checker
  # flags it as redundant. BackpexCompat re-emits our definition after Backpex's.
  KlassHeroWeb.BackpexCompat.override :confirm_label, 1 do
    @impl Backpex.ItemAction
    def confirm_label(_assigns), do: "Cancel Booking"
  end

  @impl Backpex.ItemAction
  def fields do
    [
      reason: %{
        module: Textarea,
        label: "Cancellation Reason",
        type: :string
      }
    ]
  end

  @impl Backpex.ItemAction
  def changeset(change, attrs, _metadata) do
    change
    |> cast(attrs, [:reason])
    |> validate_required([:reason])
    |> validate_length(:reason, max: 1000)
  end

  @impl Backpex.ItemAction
  def handle(socket, items, data) do
    admin_id = socket.assigns.current_scope.user.id

    results =
      Enum.map(items, fn item ->
        {item.id, KlassHero.Enrollment.cancel_enrollment_by_admin(item.id, admin_id, data.reason)}
      end)

    {successes, failures} = Enum.split_with(results, fn {_id, r} -> match?({:ok, _}, r) end)

    Enum.each(failures, fn {id, {:error, reason}} ->
      Logger.warning("[Admin.CancelBookingAction] Failed to cancel booking",
        enrollment_id: id,
        admin_id: admin_id,
        error: inspect(reason)
      )
    end)

    total = length(items)
    fail_count = length(failures)

    socket =
      cond do
        fail_count == 0 ->
          Phoenix.LiveView.put_flash(
            socket,
            :info,
            "#{total} booking(s) cancelled successfully."
          )

        fail_count == total ->
          Phoenix.LiveView.put_flash(
            socket,
            :error,
            "Could not cancel #{total} booking(s)."
          )

        true ->
          ok_count = length(successes)

          Phoenix.LiveView.put_flash(
            socket,
            :warning,
            "#{ok_count} of #{total} booking(s) cancelled. " <>
              "#{fail_count} could not be cancelled."
          )
      end

    {:ok, socket}
  end
end
