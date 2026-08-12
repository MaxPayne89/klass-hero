defmodule KlassHero.Shared.PayloadJsonbDeliveryTest do
  @moduledoc """
  The one link the rest of the suite does not cross: real `jsonb`.

  `EventTestHelper.through_outbox/1` runs a payload through `Jason`, which catches
  everything the serializer gets wrong — but it is still two in-memory maps. This
  stages through the real `ObanOutbox`, lets Postgres store `oban_jobs.args` as
  `jsonb`, reads the row back, and only then deserializes.

  Written for #1317 (atoms), following the shape of
  `program_listing_delivery_test.exs` (#1311, typed structs) one level lower: that
  one asserts a projection's rows, this one asserts the payload itself, so a failure
  names the envelope rather than whichever consumer noticed first.
  """

  use KlassHero.DataCase, async: false

  alias KlassHero.Shared.Adapters.Driven.Events.CriticalEventSerializer
  alias KlassHero.Shared.Adapters.Driven.Events.ObanOutbox
  alias KlassHero.Shared.Domain.Events.Event
  alias KlassHero.Shared.Outbox

  # Every kind that needs the sidecar to come back as itself, plus the three atoms
  # that must NOT (jsonb stores null/true/false natively, and tagging them would
  # change what `Map.get(payload, :key) || default` returns in every consumer).
  @payload %{
    type: :direct,
    message_type: :text,
    nested: %{reason: :program_ended},
    listed: ["x", :system],
    on: ~D[2026-08-12],
    at: ~T[15:00:00],
    happened_at: ~U[2026-08-12 10:00:00Z],
    price: Decimal.new("12.50"),
    title: "Chess",
    count: 7,
    active: true,
    inactive: false,
    absent: nil
  }

  test "a payload comes back out of oban_jobs.args as what the producer put in" do
    # A real topic, so Outbox.stage/2 does not drop the event for want of a consumer.
    event = Event.new(:conversation_created, :messaging, :conversation, Ecto.UUID.generate(), @payload)

    args = stage_and_read_args(event)

    assert CriticalEventSerializer.deserialize(args).payload == @payload
  end

  test "the stored payload is still plain JSON, with the types beside it" do
    event = Event.new(:conversation_created, :messaging, :conversation, Ecto.UUID.generate(), @payload)

    args = stage_and_read_args(event)

    # Readable in SQL and in Honeycomb — the reason the sidecar mirrors the payload's
    # shape instead of wrapping values inline.
    assert args["payload"]["type"] == "direct"
    assert args["payload"]["on"] == "2026-08-12"
    assert args["payload_types"]["type"] == "atom"
    assert args["payload_types"]["on"] == "date"

    # Untagged, because jsonb holds them natively.
    assert args["payload"]["absent"] == nil
    assert args["payload"]["active"] == true
    refute Map.has_key?(args["payload_types"], "absent")
    refute Map.has_key?(args["payload_types"], "active")
  end

  # Manual mode so the job is inserted and left alone: this asserts what Postgres
  # stored, not what a consumer did with it. The real outbox is swapped in around
  # the stage alone, per archive_conversations_delivery_test.exs.
  defp stage_and_read_args(event) do
    original_outbox = Application.get_env(:klass_hero, :outbox)
    Application.put_env(:klass_hero, :outbox, module: ObanOutbox)

    try do
      Oban.Testing.with_testing_mode(:manual, fn ->
        Outbox.stage(KlassHero.Messaging, event)
      end)
    after
      Application.put_env(:klass_hero, :outbox, original_outbox)
    end

    [job] = Repo.all(Oban.Job)
    [args] = job.args["events"]

    args
  end
end
