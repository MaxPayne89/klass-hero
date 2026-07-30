defmodule KlassHero.ProgramCatalog.Adapters.Driven.Projections.ProgramListingsTest do
  use KlassHero.DataCase, async: false

  import KlassHero.Factory

  alias KlassHero.ProgramCatalog.Adapters.Driven.Projections.ProgramListings
  alias KlassHero.ProgramCatalog.ProgramListing
  alias KlassHero.Repo
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

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

    # `start_projections: false` means no projection runs during the suite, so while bootstrap asked a
    # sibling GenServer for verification state it silently caught the :exit and marked every provider
    # unverified — in tests always, and in any environment where that GenServer was down.
    test "carries each program's provider verification state" do
      verified_provider = insert(:provider_profile_schema, verified: true)
      unverified_provider = insert(:provider_profile_schema)

      verified_program = insert(:program_schema, title: "Verified", provider_id: verified_provider.id)
      unverified_program = insert(:program_schema, title: "Unverified", provider_id: unverified_provider.id)

      stop_supervised!(ProgramListings)

      pid =
        start_supervised!({ProgramListings, name: :"verification_test_#{System.unique_integer([:positive])}"},
          id: :verification_bootstrap
        )

      :sys.get_state(pid)

      assert Repo.get(ProgramListing, verified_program.id).provider_verified == true
      assert Repo.get(ProgramListing, unverified_program.id).provider_verified == false
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

      dispatch("integration:program_catalog:program_created", event)

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

      dispatch("integration:program_catalog:program_created", event)
      original = Repo.get!(ProgramListing, program_id)

      # Re-dispatch the same event.
      dispatch("integration:program_catalog:program_created", event)

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
        provider_id: provider_id,
        provider_verified: false
      )

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
            registration_end_date: ~D[2026-02-28]
          }
        )

      dispatch("integration:program_catalog:program_updated", event)

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

      dispatch("integration:program_catalog:program_updated", event)

      listing = Repo.get(ProgramListing, program_id)
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

      listing_1 = insert_listing(title: "Program A", provider_id: provider_id, provider_verified: false)
      listing_2 = insert_listing(title: "Program B", provider_id: provider_id, provider_verified: false)

      # Unrelated provider's listing must not be affected.
      other_provider_id = Ecto.UUID.generate()
      other_listing = insert_listing(title: "Other Program", provider_id: other_provider_id, provider_verified: false)

      event =
        IntegrationEvent.new(
          :provider_verified,
          :provider,
          :provider,
          provider_id,
          %{provider_id: provider_id, business_name: "Test Business"}
        )

      dispatch("integration:provider:provider_verified", event)

      assert Repo.get(ProgramListing, listing_1.id).provider_verified == true
      assert Repo.get(ProgramListing, listing_2.id).provider_verified == true
      assert Repo.get(ProgramListing, other_listing.id).provider_verified == false
    end
  end

  describe "handle provider_unverified event" do
    test "sets provider_verified to false for all listings of that provider" do
      provider_id = Ecto.UUID.generate()

      listing_1 = insert_listing(title: "Program A", provider_id: provider_id, provider_verified: true)
      listing_2 = insert_listing(title: "Program B", provider_id: provider_id, provider_verified: true)

      # Unrelated provider's listing must not be affected.
      other_provider_id = Ecto.UUID.generate()
      other_listing = insert_listing(title: "Other Program", provider_id: other_provider_id, provider_verified: true)

      event =
        IntegrationEvent.new(
          :provider_unverified,
          :provider,
          :provider,
          provider_id,
          %{provider_id: provider_id, business_name: "Test Business"}
        )

      dispatch("integration:provider:provider_unverified", event)

      assert Repo.get(ProgramListing, listing_1.id).provider_verified == false
      assert Repo.get(ProgramListing, listing_2.id).provider_verified == false
      assert Repo.get(ProgramListing, other_listing.id).provider_verified == true
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

  # Broadcasts an integration event on `topic`, then blocks on :sys.get_state so
  # the projection GenServer has finished processing before assertions run.
  defp dispatch(topic, event) do
    Phoenix.PubSub.broadcast(KlassHero.PubSub, topic, {:integration_event, event})
    :sys.get_state(@test_server_name)
  end

  defp insert_listing(attrs) do
    Repo.insert!(struct!(ProgramListing, Keyword.put_new(attrs, :id, Ecto.UUID.generate())))
  end
end
