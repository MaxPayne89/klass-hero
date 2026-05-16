defmodule KlassHero.ProgramCatalog.Adapters.Driven.Projections.ProgramListingsTest do
  use KlassHero.DataCase, async: false

  import KlassHero.Factory

  alias KlassHero.ProgramCatalog.Adapters.Driven.Persistence.Schemas.ProgramListingSchema
  alias KlassHero.ProgramCatalog.Adapters.Driven.Projections.ProgramListings
  alias KlassHero.Repo
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  # Use a unique name to avoid conflicts with the supervision tree
  @test_server_name :program_listings_projection_test

  setup do
    pid = start_supervised!({ProgramListings, name: @test_server_name})
    {:ok, pid: pid}
  end

  describe "bootstrap" do
    test "projects existing programs from write table into program_listings on startup" do
      # Trigger: programs table has a FK to provider_profiles
      # Why: must create a real provider to satisfy referential integrity
      # Outcome: provider_id is valid for program_schema inserts
      provider = insert(:provider_profile_schema)

      # Insert programs into the write table BEFORE starting the projection
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

      # Stop the default test server and start a fresh one so it bootstraps
      # from the write table that now has data
      stop_supervised!(ProgramListings)

      bootstrap_name = :"bootstrap_test_#{System.unique_integer([:positive])}"

      bootstrap_pid =
        start_supervised!({ProgramListings, name: bootstrap_name}, id: :bootstrap)

      # Synchronize: ensure bootstrap has completed
      _ = :sys.get_state(bootstrap_pid)

      # Verify program_1 was projected
      listing_1 = Repo.get(ProgramListingSchema, program_1.id)
      assert listing_1 != nil
      assert listing_1.title == "Soccer Camp"
      assert listing_1.category == "sports"
      assert listing_1.provider_id == provider.id
      assert listing_1.description == "Learn soccer"
      assert listing_1.age_range == "6-10 years"
      assert listing_1.price == Decimal.new("150.00")
      assert listing_1.pricing_period == "per session"
      # Bootstrap defaults provider_verified to false
      assert listing_1.provider_verified == false

      # Verify program_2 was projected
      listing_2 = Repo.get(ProgramListingSchema, program_2.id)
      assert listing_2 != nil
      assert listing_2.title == "Art Class"
      assert listing_2.category == "education"
    end
  end

  describe "rebuild/1" do
    test "rebuilds program_listings from write table without restarting" do
      # Ensure initial bootstrap has completed before inserting test data
      _ = :sys.get_state(@test_server_name)

      provider = insert(:provider_profile_schema)

      # Insert programs into the write table after the projection has already started
      program =
        insert(:program_schema,
          title: "Rebuild Test Program",
          category: "sports",
          provider_id: provider.id
        )

      # The read table should not have this program yet (it was inserted after bootstrap)
      assert Repo.get(ProgramListingSchema, program.id) == nil

      # Rebuild should pick it up from the write table
      assert :ok = ProgramListings.rebuild(@test_server_name)

      listing = Repo.get(ProgramListingSchema, program.id)
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
        IntegrationEvent.new(
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

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:program_catalog:program_created",
        {:integration_event, event}
      )

      # Synchronize: ensure GenServer has processed the broadcast
      _ = :sys.get_state(@test_server_name)

      listing = Repo.get(ProgramListingSchema, program_id)
      assert listing != nil
      assert listing.title == "New Soccer Camp"
      assert listing.category == "sports"
      assert listing.provider_id == provider_id
      assert listing.meeting_days == ["Monday", "Wednesday"]
      assert listing.meeting_start_time == ~T[15:00:00]
      assert listing.meeting_end_time == ~T[17:00:00]
      assert listing.start_date == ~D[2026-03-01]
      assert listing.end_date == ~D[2026-06-30]
      assert listing.provider_verified == false
    end

    test "handles duplicate program_created event idempotently" do
      program_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()

      event =
        IntegrationEvent.new(
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

      # First broadcast
      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:program_catalog:program_created",
        {:integration_event, event}
      )

      _ = :sys.get_state(@test_server_name)
      original = Repo.get!(ProgramListingSchema, program_id)

      # Second broadcast of same event
      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:program_catalog:program_created",
        {:integration_event, event}
      )

      _ = :sys.get_state(@test_server_name)

      # Row still exists with preserved inserted_at
      listing = Repo.get!(ProgramListingSchema, program_id)
      assert listing.title == "Soccer Camp"
      assert listing.inserted_at == original.inserted_at
    end
  end

  describe "handle program_updated event" do
    test "updates an existing row in program_listings" do
      program_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()

      # Insert an existing listing with season pre-set (from bootstrap)
      Repo.insert!(%ProgramListingSchema{
        id: program_id,
        title: "Old Title",
        category: "sports",
        season: "Spring 2026",
        provider_id: provider_id,
        provider_verified: false
      })

      event =
        IntegrationEvent.new(
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
            registration_end_date: ~D[2026-02-28],
            instructor: %{
              name: "Coach Smith",
              headshot_url: "https://example.com/coach.jpg"
            }
          }
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:program_catalog:program_updated",
        {:integration_event, event}
      )

      # Synchronize: ensure GenServer has processed the broadcast
      _ = :sys.get_state(@test_server_name)

      listing = Repo.get(ProgramListingSchema, program_id)
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
      assert listing.instructor_name == "Coach Smith"
      assert listing.instructor_headshot_url == "https://example.com/coach.jpg"
    end

    test "creates new listing when program_id has no pre-existing row (upsert)" do
      program_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()

      event =
        IntegrationEvent.new(
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

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:program_catalog:program_updated",
        {:integration_event, event}
      )

      _ = :sys.get_state(@test_server_name)

      listing = Repo.get(ProgramListingSchema, program_id)
      assert listing != nil
      assert listing.title == "Fresh Program"
      assert listing.description == "Created via update event"
      assert listing.category == "education"
      assert listing.provider_id == provider_id
      assert listing.season == nil
      assert listing.provider_verified == false
    end
  end

  describe "handle provider_verified event" do
    test "sets provider_verified to true for all listings of that provider" do
      provider_id = Ecto.UUID.generate()

      # Insert listings with provider_verified = false
      listing_1 =
        Repo.insert!(%ProgramListingSchema{
          id: Ecto.UUID.generate(),
          title: "Program A",
          provider_id: provider_id,
          provider_verified: false
        })

      listing_2 =
        Repo.insert!(%ProgramListingSchema{
          id: Ecto.UUID.generate(),
          title: "Program B",
          provider_id: provider_id,
          provider_verified: false
        })

      # Unrelated provider's listing should not be affected
      other_provider_id = Ecto.UUID.generate()

      other_listing =
        Repo.insert!(%ProgramListingSchema{
          id: Ecto.UUID.generate(),
          title: "Other Program",
          provider_id: other_provider_id,
          provider_verified: false
        })

      event =
        IntegrationEvent.new(
          :provider_verified,
          :provider,
          :provider,
          provider_id,
          %{provider_id: provider_id, business_name: "Test Business"}
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:provider:provider_verified",
        {:integration_event, event}
      )

      # Synchronize: ensure GenServer has processed the broadcast
      _ = :sys.get_state(@test_server_name)

      assert Repo.get(ProgramListingSchema, listing_1.id).provider_verified == true
      assert Repo.get(ProgramListingSchema, listing_2.id).provider_verified == true
      # Other provider's listing should remain unchanged
      assert Repo.get(ProgramListingSchema, other_listing.id).provider_verified == false
    end
  end

  describe "handle provider_unverified event" do
    test "sets provider_verified to false for all listings of that provider" do
      provider_id = Ecto.UUID.generate()

      # Insert listings with provider_verified = true
      listing_1 =
        Repo.insert!(%ProgramListingSchema{
          id: Ecto.UUID.generate(),
          title: "Program A",
          provider_id: provider_id,
          provider_verified: true
        })

      listing_2 =
        Repo.insert!(%ProgramListingSchema{
          id: Ecto.UUID.generate(),
          title: "Program B",
          provider_id: provider_id,
          provider_verified: true
        })

      # Unrelated provider's listing should not be affected
      other_provider_id = Ecto.UUID.generate()

      other_listing =
        Repo.insert!(%ProgramListingSchema{
          id: Ecto.UUID.generate(),
          title: "Other Program",
          provider_id: other_provider_id,
          provider_verified: true
        })

      event =
        IntegrationEvent.new(
          :provider_unverified,
          :provider,
          :provider,
          provider_id,
          %{provider_id: provider_id, business_name: "Test Business"}
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:provider:provider_unverified",
        {:integration_event, event}
      )

      # Synchronize: ensure GenServer has processed the broadcast
      _ = :sys.get_state(@test_server_name)

      assert Repo.get(ProgramListingSchema, listing_1.id).provider_verified == false
      assert Repo.get(ProgramListingSchema, listing_2.id).provider_verified == false
      # Other provider's listing should remain unchanged
      assert Repo.get(ProgramListingSchema, other_listing.id).provider_verified == true
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
      :sys.get_state(pid)

      # If any rescue path was triggered during bootstrap, retry_count would be > 0.
      assert %{bootstrapped: true, retry_count: 0} = :sys.get_state(pid)

      # Send one well-formed event; confirm the dispatcher path doesn't trip an internal raise.
      program_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()

      event =
        IntegrationEvent.new(
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

      send(pid, {:integration_event, event})
      :sys.get_state(pid)

      # No retry was scheduled by handle_event; state invariant preserved.
      assert %{bootstrapped: true, retry_count: 0} = :sys.get_state(pid)
    end
  end
end
