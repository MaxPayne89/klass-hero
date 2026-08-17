defmodule KlassHero.ProgramCatalog.Adapters.Driven.Projections.ProgramListingsTest do
  use KlassHero.DataCase, async: false

  import KlassHero.EventTestHelper, only: [through_outbox: 1]
  import KlassHero.Factory

  alias KlassHero.ProgramCatalog.Adapters.Driven.Projections.ProgramListings
  alias KlassHero.ProgramCatalog.Domain.Events.ProgramEvents
  alias KlassHero.ProgramCatalog.ProgramListing
  alias KlassHero.Repo
  alias KlassHero.Shared.Domain.Events.Event

  # Unique name to avoid conflicts with the supervision tree.
  @test_server_name :program_listings_projection_test

  setup do
    pid = start_supervised!({ProgramListings, name: @test_server_name})
    {:ok, pid: pid}
  end

  describe "bootstrap" do
    test "projects existing programs from write table into program_listings on startup" do
      # program_schema has a FK to provider_profiles, so a real provider is required.
      provider = insert(:provider_profile_schema)

      # Insert into the write table BEFORE starting the projection.
      program_1 =
        insert(:program_schema,
          title: "Soccer Camp",
          category: "sports",
          provider_id: provider.id,
          description: "Learn soccer",
          age_range: "6-10 years",
          price: Decimal.new("150.00"),
          pricing_period: "per session"
        )

      program_2 =
        insert(:program_schema,
          title: "Art Class",
          category: "education",
          provider_id: provider.id
        )

      # Restart the projection so it bootstraps from the now-populated write table.
      stop_supervised!(ProgramListings)

      bootstrap_name = :"bootstrap_test_#{System.unique_integer([:positive])}"

      bootstrap_pid =
        start_supervised!({ProgramListings, name: bootstrap_name}, id: :bootstrap)

      :sys.get_state(bootstrap_pid)

      listing_1 = Repo.get(ProgramListing, program_1.id)
      assert listing_1 != nil
      assert listing_1.title == "Soccer Camp"
      assert listing_1.category == "sports"
      assert listing_1.provider_id == provider.id
      assert listing_1.description == "Learn soccer"
      assert listing_1.age_range == "6-10 years"
      assert listing_1.price == Decimal.new("150.00")
      assert listing_1.pricing_period == "per session"

      listing_2 = Repo.get(ProgramListing, program_2.id)
      assert listing_2 != nil
      assert listing_2.title == "Art Class"
      assert listing_2.category == "education"
    end
  end

  describe "rebuild/1" do
    test "rebuilds program_listings from write table without restarting" do
      # Drain the initial bootstrap before inserting test data.
      :sys.get_state(@test_server_name)

      provider = insert(:provider_profile_schema)

      program =
        insert(:program_schema,
          title: "Rebuild Test Program",
          category: "sports",
          provider_id: provider.id
        )

      # Not projected yet — inserted after bootstrap.
      assert Repo.get(ProgramListing, program.id) == nil

      assert :ok = ProgramListings.rebuild(@test_server_name)

      listing = Repo.get(ProgramListing, program.id)
      assert listing != nil
      assert listing.title == "Rebuild Test Program"
      assert listing.category == "sports"
      assert listing.provider_id == provider.id
    end
  end

  describe "handle program_created event" do
    test "inserts a new row into program_listings" do
      program_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()

      event =
        Event.new(
          :program_created,
          :program_catalog,
          :program,
          program_id,
          %{
            program_id: program_id,
            provider_id: provider_id,
            title: "New Soccer Camp",
            category: "sports",
            meeting_days: ["Monday", "Wednesday"],
            meeting_start_time: ~T[15:00:00],
            meeting_end_time: ~T[17:00:00],
            start_date: ~D[2026-03-01],
            end_date: ~D[2026-06-30]
          }
        )

      dispatch(event)

      listing = Repo.get(ProgramListing, program_id)
      assert listing != nil
      assert listing.title == "New Soccer Camp"
      assert listing.category == "sports"
      assert listing.provider_id == provider_id
      assert listing.meeting_days == ["Monday", "Wednesday"]
      assert listing.meeting_start_time == ~T[15:00:00]
      assert listing.meeting_end_time == ~T[17:00:00]
      assert listing.start_date == ~D[2026-03-01]
      assert listing.end_date == ~D[2026-06-30]
    end

    test "handles duplicate program_created event idempotently" do
      program_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()

      event =
        Event.new(
          :program_created,
          :program_catalog,
          :program,
          program_id,
          %{
            program_id: program_id,
            provider_id: provider_id,
            title: "Soccer Camp",
            category: "sports",
            meeting_days: []
          }
        )

      dispatch(event)
      original = Repo.get!(ProgramListing, program_id)

      # Re-dispatch the same event.
      dispatch(event)

      # Row still exists with preserved inserted_at.
      listing = Repo.get!(ProgramListing, program_id)
      assert listing.title == "Soccer Camp"
      assert listing.inserted_at == original.inserted_at
    end
  end

  describe "handle program_updated event" do
    test "updates an existing row in program_listings" do
      program_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()

      # Existing listing with season pre-set (from bootstrap).
      insert_listing(
        id: program_id,
        title: "Old Title",
        category: "sports",
        season: "Spring 2026",
        provider_id: provider_id
      )

      event =
        Event.new(
          :program_updated,
          :program_catalog,
          :program,
          program_id,
          %{
            program_id: program_id,
            provider_id: provider_id,
            title: "Updated Soccer Camp",
            description: "Now with more drills",
            category: "sports",
            age_range: "7-12 years",
            price: Decimal.new("200.00"),
            pricing_period: "per month",
            location: "City Park",
            cover_image_url: "https://example.com/cover.jpg",
            start_date: ~D[2026-03-01],
            end_date: ~D[2026-06-30],
            meeting_days: ["Tuesday", "Thursday"],
            meeting_start_time: ~T[16:00:00],
            meeting_end_time: ~T[18:00:00],
            season: "Spring 2026",
            registration_start_date: ~D[2026-02-01],
            registration_end_date: ~D[2026-02-28]
          }
        )

      dispatch(event)

      listing = Repo.get(ProgramListing, program_id)
      assert listing.title == "Updated Soccer Camp"
      assert listing.description == "Now with more drills"
      assert listing.category == "sports"
      assert listing.age_range == "7-12 years"
      assert listing.price == Decimal.new("200.00")
      assert listing.pricing_period == "per month"
      assert listing.location == "City Park"
      assert listing.cover_image_url == "https://example.com/cover.jpg"
      assert listing.start_date == ~D[2026-03-01]
      assert listing.end_date == ~D[2026-06-30]
      assert listing.meeting_days == ["Tuesday", "Thursday"]
      assert listing.meeting_start_time == ~T[16:00:00]
      assert listing.meeting_end_time == ~T[18:00:00]
      assert listing.season == "Spring 2026"
      assert listing.registration_start_date == ~D[2026-02-01]
      assert listing.registration_end_date == ~D[2026-02-28]
    end

    test "creates new listing when program_id has no pre-existing row (upsert)" do
      program_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()

      event =
        Event.new(
          :program_updated,
          :program_catalog,
          :program,
          program_id,
          %{
            program_id: program_id,
            provider_id: provider_id,
            title: "Fresh Program",
            description: "Created via update event",
            category: "education",
            meeting_days: ["Monday"],
            meeting_start_time: ~T[10:00:00],
            meeting_end_time: ~T[12:00:00]
          }
        )

      dispatch(event)

      listing = Repo.get(ProgramListing, program_id)
      assert listing != nil
      assert listing.title == "Fresh Program"
      assert listing.description == "Created via update event"
      assert listing.category == "education"
      assert listing.provider_id == provider_id
      assert listing.season == nil
    end
  end

  # The tests above hand a native %Event{} to the projection. Production does not:
  # the event is staged into oban_jobs.args and read back out first, which is where
  # #1311's %Date{} became "2026-03-01". These use the real event constructors and
  # cross that boundary.
  describe "events crossing the outbox boundary" do
    test "projects a program_created carrying dates, times and a price" do
      program_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()

      ProgramEvents.program_created(program_id, %{
        provider_id: provider_id,
        title: "Soccer Camp",
        category: "sports",
        meeting_days: ["Monday"],
        meeting_start_time: ~T[15:00:00],
        meeting_end_time: ~T[17:00:00],
        start_date: ~D[2026-08-12],
        end_date: ~D[2026-09-30]
      })
      |> through_outbox()
      |> dispatch()

      listing = Repo.get!(ProgramListing, program_id)
      assert listing.start_date == ~D[2026-08-12]
      assert listing.end_date == ~D[2026-09-30]
      assert listing.meeting_start_time == ~T[15:00:00]
      assert listing.meeting_end_time == ~T[17:00:00]
    end

    test "projects a program_updated carrying every typed field" do
      program_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()

      ProgramEvents.program_updated(program_id, %{
        provider_id: provider_id,
        title: "Updated Soccer Camp",
        category: "sports",
        price: Decimal.new("200.00"),
        meeting_days: ["Tuesday"],
        meeting_start_time: ~T[16:00:00],
        meeting_end_time: ~T[18:00:00],
        start_date: ~D[2026-08-12],
        end_date: ~D[2026-09-30],
        registration_start_date: ~D[2026-07-01],
        registration_end_date: ~D[2026-07-31]
      })
      |> through_outbox()
      |> dispatch()

      listing = Repo.get!(ProgramListing, program_id)
      assert listing.price == Decimal.new("200.00")
      assert listing.start_date == ~D[2026-08-12]
      assert listing.end_date == ~D[2026-09-30]
      assert listing.meeting_start_time == ~T[16:00:00]
      assert listing.registration_start_date == ~D[2026-07-01]
      assert listing.registration_end_date == ~D[2026-07-31]
    end

    # #1376: the read column was varchar(255) while the write side allows 500, so a
    # storage URL over the limit raised 22001 here, exhausted all ten Oban attempts
    # and discarded the update *whole* — location stayed stale too, not just the image.
    test "projects a cover_image_url longer than 255 characters" do
      program_id = Ecto.UUID.generate()

      url =
        "https://storage.example.com/program_covers/providers/#{Ecto.UUID.generate()}/" <>
          String.duplicate("a", 240) <> ".jpg"

      assert String.length(url) > 255

      ProgramEvents.program_updated(program_id, %{
        provider_id: Ecto.UUID.generate(),
        title: "Soccer Camp",
        location: "Online",
        cover_image_url: url
      })
      |> through_outbox()
      |> dispatch()

      listing = Repo.get!(ProgramListing, program_id)
      assert listing.cover_image_url == url
      assert listing.location == "Online"
    end
  end

  describe "macro invariants after happy-path startup" do
    test "state.retry_count == 0 after first event projects successfully" do
      # Start WITHOUT skip_bootstrap to exercise the real subscribe + handle_continue path.
      # If a KeyError-class bug got swallowed by the retry mixin's rescue, retry_count
      # would be > 0 even though the test event still projects correctly.
      pid =
        start_supervised!(
          {ProgramListings, name: :"reg_#{System.unique_integer([:positive])}"},
          id: :regression_projection
        )

      # Drain handle_continue; bootstrap should succeed on the first attempt.
      # Shared sandbox (async: false) covers the GenServer pid automatically.
      :sys.get_state(pid)

      # If any rescue path was triggered during bootstrap, retry_count would be > 0.
      assert %{bootstrapped: true, retry_count: 0} = :sys.get_state(pid)

      # Send one well-formed event; confirm the dispatcher path doesn't trip an internal raise.
      program_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()

      event =
        Event.new(
          :program_created,
          :program_catalog,
          :program,
          program_id,
          %{
            program_id: program_id,
            provider_id: provider_id,
            title: "Regression Test Program",
            category: "sports",
            meeting_days: []
          }
        )

      assert :ok = ProgramListings.project(event)
      assert Repo.get(ProgramListing, program_id)

      # Projecting is not a message to this process, so its bootstrap state is untouched.
      assert %{bootstrapped: true, retry_count: 0} = :sys.get_state(pid)
    end
  end

  # Projects in the test process, exactly as the delivery job does. No broadcast and
  # no mailbox fence: the projection GenServer is not in this path at all.
  defp dispatch(event), do: ProgramListings.project(event)

  defp insert_listing(attrs) do
    Repo.insert!(struct!(ProgramListing, Keyword.put_new(attrs, :id, Ecto.UUID.generate())))
  end
end
