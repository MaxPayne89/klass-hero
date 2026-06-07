defmodule KlassHero.ProgramCatalog.CreateProgramIntegrationTest do
  use KlassHero.DataCase

  import KlassHero.EventTestHelper

  alias KlassHero.ProgramCatalog
  alias KlassHero.ProviderFixtures

  describe "create_program/1" do
    setup do
      provider = ProviderFixtures.provider_profile_fixture()
      %{provider: provider}
    end

    test "creates program with required fields", %{provider: provider} do
      assert {:ok, program} =
               ProgramCatalog.create_program(%{
                 provider_id: provider.id,
                 title: "Art Adventures",
                 description: "Creative art program for kids",
                 category: "arts",
                 price: Decimal.new("50.00")
               })

      assert program.title == "Art Adventures"
      assert program.category == "arts"
      assert program.instructor == nil
    end

    test "creates program with instructor", %{provider: provider} do
      staff = ProviderFixtures.staff_member_fixture(provider_id: provider.id)

      assert {:ok, program} =
               ProgramCatalog.create_program(%{
                 provider_id: provider.id,
                 title: "Soccer Camp",
                 description: "Learn to play soccer",
                 category: "sports",
                 price: Decimal.new("75.00"),
                 location: "Sports Park",
                 instructor: %{
                   id: staff.id,
                   name: "#{staff.first_name} #{staff.last_name}",
                   headshot_url: staff.headshot_url
                 }
               })

      assert program.instructor != nil
      assert program.instructor.id == staff.id
      assert program.location == "Sports Park"
    end

    test "rejects missing required fields" do
      assert {:error, errors} = ProgramCatalog.create_program(%{title: "Incomplete"})

      assert is_list(errors)
      assert Enum.any?(errors, &String.contains?(&1, "description"))
      assert Enum.any?(errors, &String.contains?(&1, "category"))
      assert Enum.any?(errors, &String.contains?(&1, "price"))
      assert Enum.any?(errors, &String.contains?(&1, "rovider"))
    end

    test "rejects negative price", %{provider: provider} do
      assert {:error, errors} =
               ProgramCatalog.create_program(%{
                 provider_id: provider.id,
                 title: "Bad Price Program",
                 description: "Has negative price",
                 category: "arts",
                 price: Decimal.new("-5.00")
               })

      assert is_list(errors)
      assert Enum.any?(errors, &String.contains?(&1, "rice"))
    end

    test "rejects invalid category", %{provider: provider} do
      assert {:error, errors} =
               ProgramCatalog.create_program(%{
                 provider_id: provider.id,
                 title: "Test",
                 description: "Test desc",
                 category: "invalid_category",
                 price: Decimal.new("10.00")
               })

      assert is_list(errors)
      assert Enum.any?(errors, &String.contains?(&1, "ategory"))
    end

    test "accepts all valid program categories", %{provider: provider} do
      categories = ["sports", "arts", "music", "education", "life-skills", "camps", "workshops"]

      for category <- categories do
        assert {:ok, program} =
                 ProgramCatalog.create_program(%{
                   provider_id: provider.id,
                   title: "Program for #{category}",
                   description: "Testing #{category} category",
                   category: category,
                   price: Decimal.new("25.00")
                 })

        assert program.category == category
      end
    end

    test "dispatches program_created integration event on success", %{provider: provider} do
      setup_test_integration_events()

      assert {:ok, program} =
               ProgramCatalog.create_program(%{
                 provider_id: provider.id,
                 title: "Event Test Program",
                 description: "Tests event dispatch",
                 category: "arts",
                 price: Decimal.new("30.00")
               })

      event = assert_integration_event_published(:program_created)
      assert event.entity_id == program.id
      assert event.payload.provider_id == program.provider_id
      assert event.payload.title == "Event Test Program"
    end
  end

  describe "create_program/1 without program limits" do
    # Provider tiers removed (ADR-0004): no per-tier program cap remains
    test "former starter-tier provider creates programs beyond the old cap" do
      provider = ProviderFixtures.provider_profile_fixture(%{subscription_tier: "starter"})

      for i <- 1..3 do
        assert {:ok, program} =
                 ProgramCatalog.create_program(%{
                   provider_id: provider.id,
                   title: "Program #{i}",
                   description: "A valid program",
                   category: "arts",
                   price: Decimal.new("50.00")
                 }),
               "expected program #{i} to be created (former cap was 2)"

        assert program.origin == :self_posted
      end
    end
  end
end
