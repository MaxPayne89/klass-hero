defmodule KlassHero.ProgramCatalog.ProgramListingDeliveryTest do
  @moduledoc """
  Integration test for #1311, at the level the bug actually lived: creating a program
  stages `program_created` in the write's transaction, and the delivery job reads it
  back out of `oban_jobs.args` before invoking `ProgramListings.project/1`.

  Every other test of this path either hands the projection a native `%Event{}` or
  asserts on `TestOutbox`, which records structs rather than enqueueing them. Neither
  crosses the jsonb boundary, which is why a `%Date{}` arriving as `"2026-08-12"` —
  raising `Ecto.ChangeError` on every program create and update in production — passed
  CI for two months. This test swaps in the real `ObanOutbox`, following
  `test/klass_hero/messaging/archive_conversations_delivery_test.exs`.
  """

  use KlassHero.DataCase, async: false

  alias KlassHero.ProgramCatalog
  alias KlassHero.ProgramCatalog.ProgramListing
  alias KlassHero.ProviderFixtures
  alias KlassHero.Shared.Adapters.Driven.Events.ObanOutbox

  describe "creating a program" do
    test "projects its dates and price into the catalog read table" do
      provider = ProviderFixtures.provider_profile_fixture()

      {:ok, program} =
        create_and_deliver(%{
          provider_id: provider.id,
          title: "Soccer Camp",
          description: "Outdoor soccer for beginners",
          category: "sports",
          price: Decimal.new("150.00"),
          start_date: ~D[2026-08-12],
          end_date: ~D[2026-09-30],
          meeting_start_time: ~T[15:00:00],
          meeting_end_time: ~T[17:00:00]
        })

      listing = Repo.get(ProgramListing, program.id)

      assert listing != nil,
             "program_created was staged but never reached program_listings — the delivery job failed"

      assert listing.start_date == ~D[2026-08-12]
      assert listing.end_date == ~D[2026-09-30]
      assert listing.meeting_start_time == ~T[15:00:00]
      assert listing.meeting_end_time == ~T[17:00:00]
    end
  end

  # Swapped around the act alone, and manual-mode-then-drain rather than the suite's
  # `testing: :inline`, which would run delivery inside the producer's own transaction.
  # See archive_conversations_delivery_test.exs for both reasons in full.
  defp create_and_deliver(attrs) do
    original_outbox = Application.get_env(:klass_hero, :outbox)
    Application.put_env(:klass_hero, :outbox, module: ObanOutbox)

    result =
      try do
        Oban.Testing.with_testing_mode(:manual, fn -> ProgramCatalog.create_program(attrs) end)
      after
        Application.put_env(:klass_hero, :outbox, original_outbox)
      end

    Oban.drain_queue(queue: :events, with_recursion: true)

    result
  end
end
