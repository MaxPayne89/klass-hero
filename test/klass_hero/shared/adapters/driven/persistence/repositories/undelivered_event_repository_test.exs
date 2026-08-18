defmodule KlassHero.Shared.Adapters.Driven.Persistence.Repositories.UndeliveredEventRepositoryTest do
  @moduledoc """
  The dead-letter store, and the two properties replay depends on.

  A row can be written twice — the first failure, then a replay that failed again —
  and the second write has to *refresh* it. Under `on_conflict: :nothing` it did
  not, so the page kept showing the first failure's consumers and timestamp while
  claiming to describe the current state.

  What must survive that refresh is the other half: `replayed_at`, because it means
  "was ever replayed" and is what exempts an unnoticed row from the prune, and
  `inserted_at`, because restarting the retention clock on every re-failure would
  hold personal data for as long as the event kept failing.
  """

  use KlassHero.DataCase, async: true

  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.Repositories.UndeliveredEventRepository
  alias KlassHero.Shared.Adapters.Driven.Persistence.Schemas.UndeliveredEvent

  describe "record_all/1" do
    test "records a row for an event delivery gave up on" do
      event_id = Ecto.UUID.generate()

      assert :ok = UndeliveredEventRepository.record_all([row(event_id)])

      assert %UndeliveredEvent{topic: "integration:test:thing"} = get(event_id)
    end

    test "refreshes the outstanding work when the same event fails again" do
      event_id = Ecto.UUID.generate()
      later = DateTime.add(DateTime.utc_now(), 1, :hour)

      :ok = UndeliveredEventRepository.record_all([row(event_id)])

      :ok =
        UndeliveredEventRepository.record_all([
          row(event_id, missed_consumers: ["Elixir.Other:handle_event"], job_id: 99, discarded_at: later)
        ])

      refreshed = get(event_id)
      assert refreshed.missed_consumers == ["Elixir.Other:handle_event"]
      assert refreshed.job_id == 99
      assert DateTime.compare(refreshed.discarded_at, later) == :eq
    end

    # The stamp means "was ever replayed" and nothing but this could clear it. If a
    # re-failure did, every surviving row would read as unreplayed and the prune's
    # exemption would spare all of them forever.
    test "leaves an earlier replay stamp standing when the event fails again" do
      event_id = Ecto.UUID.generate()
      :ok = UndeliveredEventRepository.record_all([row(event_id)])
      :ok = UndeliveredEventRepository.mark_replayed(event_id)
      stamped = get(event_id).replayed_at

      :ok = UndeliveredEventRepository.record_all([row(event_id, job_id: 99)])

      assert DateTime.compare(get(event_id).replayed_at, stamped) == :eq
    end

    # Retention counts from the first failure. Refreshing this would hold the payload
    # for as long as the event kept failing, which is the opposite of a retention rule.
    test "does not restart the retention clock when the event fails again" do
      event_id = Ecto.UUID.generate()
      staged_at = DateTime.add(DateTime.utc_now(), -30, :day)

      :ok = UndeliveredEventRepository.record_all([row(event_id, inserted_at: staged_at)])
      :ok = UndeliveredEventRepository.record_all([row(event_id, job_id: 99)])

      assert DateTime.compare(get(event_id).inserted_at, staged_at) == :eq
    end
  end

  describe "mark_replayed/1" do
    test "stamps the row so the prune can tell it apart from one nobody noticed" do
      event_id = Ecto.UUID.generate()
      :ok = UndeliveredEventRepository.record_all([row(event_id)])

      assert :ok = UndeliveredEventRepository.mark_replayed(event_id)

      assert get(event_id).replayed_at
    end
  end

  describe "resolve/1" do
    test "deletes the row once every missed consumer has landed" do
      event_id = Ecto.UUID.generate()
      :ok = UndeliveredEventRepository.record_all([row(event_id)])

      assert :ok = UndeliveredEventRepository.resolve(event_id)

      refute get(event_id)
    end

    test "is a no-op for an event that was already resolved" do
      assert :ok = UndeliveredEventRepository.resolve(Ecto.UUID.generate())
    end
  end

  describe "prune/2" do
    # Age alone no longer decides. A replayed row expires on the ordinary rule; an
    # unreplayed one is held, because nothing but a person is going to notice it and
    # pruning it takes the payload they would have needed. The backstop is what keeps
    # "held" from meaning "kept forever".
    @cases [
      {"a replayed row past the cutoff", 100, true, false},
      {"a replayed row inside the cutoff", 10, true, true},
      {"an unreplayed row past the cutoff", 100, false, true},
      {"an unreplayed row past the backstop", 400, false, false}
    ]

    for {description, age_days, replayed?, kept?} <- @cases do
      test "#{description} is #{if kept?, do: "kept", else: "pruned"}" do
        event_id = staged(unquote(age_days), unquote(replayed?))

        UndeliveredEventRepository.prune(cutoff(90), cutoff(365))

        assert get(event_id) != nil == unquote(kept?),
               "expected #{unquote(description)} to be #{unquote(if kept?, do: "kept", else: "pruned")}"
      end
    end

    test "returns how many rows it deleted" do
      staged(100, true)
      staged(100, true)
      staged(100, false)

      assert UndeliveredEventRepository.prune(cutoff(90), cutoff(365)) == 2
    end
  end

  describe "count_held/2" do
    test "counts the unreplayed rows the exemption spared" do
      staged(100, false)
      staged(100, true)
      staged(10, false)

      assert UndeliveredEventRepository.count_held(cutoff(90), cutoff(365)) == 1
    end
  end

  defp cutoff(days), do: DateTime.add(DateTime.utc_now(), -days, :day)

  defp staged(age_days, replayed?) do
    event_id = Ecto.UUID.generate()
    staged_at = DateTime.add(DateTime.utc_now(), -age_days, :day)

    :ok = UndeliveredEventRepository.record_all([row(event_id, inserted_at: staged_at)])
    if replayed?, do: :ok = UndeliveredEventRepository.mark_replayed(event_id)

    event_id
  end

  defp row(event_id, overrides \\ []) do
    now = DateTime.utc_now()

    Enum.into(overrides, %{
      event_id: event_id,
      topic: "integration:test:thing",
      payload: %{"event_id" => event_id},
      missed_consumers: ["Elixir.Whoever:handle_event"],
      job_id: 1,
      discarded_at: now,
      inserted_at: now
    })
  end

  defp get(event_id), do: Repo.get_by(UndeliveredEvent, event_id: event_id)
end
