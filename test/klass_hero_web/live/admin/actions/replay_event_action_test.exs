defmodule KlassHeroWeb.Admin.Actions.ReplayEventActionTest do
  @moduledoc """
  The admin's exit from a permanently-failed delivery.

  What the flashes have to keep apart is "re-delivery is running" from "nothing was
  enqueued". A replay whose consumers have since been retired cannot be run, and the
  page it is triggered from would otherwise show the row unchanged either way.
  """

  use KlassHero.DataCase, async: false

  alias KlassHero.Accounts.Scope
  alias KlassHero.AccountsFixtures
  alias KlassHero.Shared.Adapters.Driven.Events.EventConsumerRegistry
  alias KlassHero.Shared.Adapters.Driven.Persistence.Repositories.UndeliveredEventRepository
  alias KlassHero.Shared.Adapters.Driven.Persistence.Schemas.UndeliveredEvent
  alias KlassHero.Shared.EventDispatcher
  alias KlassHeroWeb.Admin.Actions.ReplayEventAction
  alias Phoenix.LiveView.Socket

  @topic "integration:accounts:user_registered"

  setup do
    admin = AccountsFixtures.user_fixture(%{is_admin: true})

    socket = %Socket{
      assigns: %{__changed__: %{}, flash: %{}, current_scope: Scope.for_user(admin)},
      private: %{live_temp: %{}}
    }

    %{socket: socket}
  end

  describe "handle/3" do
    test "all replayed — info flash with count", %{socket: socket} do
      items = [replayable(), replayable()]

      assert {:ok, socket} = handle(socket, items)
      assert socket.assigns.flash["info"] == "2 event(s) queued for re-delivery."
    end

    test "all refused — error flash naming the reason", %{socket: socket} do
      items = [retired(), retired()]

      assert {:ok, socket} = handle(socket, items)

      assert socket.assigns.flash["error"] ==
               "Could not replay 2 event(s): they name consumers that are no longer registered."
    end

    test "partial refusal — warning flash with counts", %{socket: socket} do
      items = [replayable(), retired()]

      assert {:ok, socket} = handle(socket, items)

      assert socket.assigns.flash["warning"] ==
               "1 of 2 event(s) queued for re-delivery. " <>
                 "1 name consumers that are no longer registered."
    end

    # The flash reports the class; the row itself still lists the refs, and so does the
    # log. What must not happen is the refusal reading as a success.
    test "a refusal enqueues nothing", %{socket: socket} do
      row = retired()

      {:ok, _socket} = handle(socket, [row])

      assert [] = Repo.all(Oban.Job)
      refute Repo.get_by(UndeliveredEvent, event_id: row.event_id).replayed_at
    end
  end

  # `testing: :inline` would run the delivery at insert, executing the real consumers
  # against a fabricated envelope — a sequencing production never has.
  defp handle(socket, items) do
    Oban.Testing.with_testing_mode(:manual, fn ->
      ReplayEventAction.handle(socket, items, %{})
    end)
  end

  defp replayable do
    refs = for consumer <- EventConsumerRegistry.consumers_for(@topic), do: EventDispatcher.handler_ref(consumer)

    record(refs)
  end

  defp retired, do: record(["Elixir.KlassHero.Gone.Handler:handle_event"])

  defp record(missed_consumers) do
    event_id = Ecto.UUID.generate()
    now = DateTime.utc_now()

    :ok =
      UndeliveredEventRepository.record_all([
        %{
          event_id: event_id,
          topic: @topic,
          payload: %{"event_id" => event_id},
          missed_consumers: missed_consumers,
          job_id: 1,
          discarded_at: now,
          inserted_at: now
        }
      ])

    Repo.get_by(UndeliveredEvent, event_id: event_id)
  end
end
