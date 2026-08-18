defmodule KlassHeroWeb.Admin.Actions.ReplayEventAction do
  @moduledoc """
  Backpex item action re-delivering a permanently-failed integration event.

  The exit `UndeliveredEventLive` used to name and not offer: before this, making
  the missed consumers run meant opening a production shell and hand-writing an
  `Oban.insert`.

  Safe to press twice. `EventDispatcher` gates every consumer on `processed_events`,
  so a replay re-runs only the ones that never succeeded — which is also why no
  confirmation of *scope* is needed, only of intent.

  Selectable in bulk because one incident produces several rows: #1376 discarded
  three delivery jobs at once.

  ## Refusal is a failure, not a quiet success

  `EventReplay.replay/1` refuses a row naming a consumer that has since left
  `:event_consumers`, because delivering to an unrouted topic reports `:ok` having
  done nothing. The flash reports that class rather than the refs — the row already
  lists them, and a bulk refusal would otherwise put a paragraph of fully-qualified
  module names in a toast. The log keeps the refs.
  """

  use BackpexWeb, :item_action

  alias KlassHero.Shared.EventReplay

  require KlassHeroWeb.BackpexCompat
  require Logger

  @impl Backpex.ItemAction
  def icon(assigns, _item) do
    ~H"""
    <Backpex.HTML.CoreComponents.icon name="hero-arrow-path" class="h-5 w-5 text-blue-600" />
    """
  end

  @impl Backpex.ItemAction
  def label(_assigns, _item), do: "Replay"

  @impl Backpex.ItemAction
  def confirm(_assigns) do
    "This re-runs only the consumers that never succeeded; the ones that already ran " <>
      "are skipped. Are you sure?"
  end

  # See the note in CancelBookingAction — Backpex appends a default confirm_label/1.
  KlassHeroWeb.BackpexCompat.override :confirm_label, 1 do
    @impl Backpex.ItemAction
    def confirm_label(_assigns), do: "Replay"
  end

  @impl Backpex.ItemAction
  def handle(socket, items, _data) do
    admin_id = socket.assigns.current_scope.user.id
    results = Enum.map(items, fn item -> {item, EventReplay.replay(item)} end)
    failures = Enum.reject(results, fn {_item, result} -> result == :ok end)

    Enum.each(failures, &log_refusal(&1, admin_id))

    {:ok, Phoenix.LiveView.put_flash(socket, level(failures, items), message(failures, items))}
  end

  defp log_refusal({item, {:error, {:retired_consumers, refs}}}, admin_id) do
    Logger.warning("[Admin.ReplayEventAction] Refused to replay an event with retired consumers",
      event_id: item.event_id,
      topic: item.topic,
      retired_consumers: inspect(refs),
      admin_id: admin_id
    )
  end

  defp level([], _items), do: :info
  defp level(failures, items) when length(failures) == length(items), do: :error
  defp level(_failures, _items), do: :warning

  defp message([], items), do: "#{length(items)} event(s) queued for re-delivery."

  defp message(failures, items) when length(failures) == length(items) do
    "Could not replay #{length(items)} event(s): they name consumers that are no longer registered."
  end

  defp message(failures, items) do
    ok_count = length(items) - length(failures)

    "#{ok_count} of #{length(items)} event(s) queued for re-delivery. " <>
      "#{length(failures)} name consumers that are no longer registered."
  end
end
