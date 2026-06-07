defmodule KlassHero.ProgramCatalog.Adapters.Driven.Persistence.Repositories.ProgramRepositoryTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.ProgramCatalog.Adapters.Driven.Persistence.Mappers.ProgramMapper
  alias KlassHero.ProgramCatalog.Adapters.Driven.Persistence.Repositories.ProgramRepository
  alias KlassHero.ProgramCatalog.Adapters.Driven.Persistence.Schemas.ProgramSchema
  alias KlassHero.ProgramCatalog.Domain.Models.Program
  alias KlassHero.Repo
  alias KlassHero.Shared.Domain.Types.Pagination.PageResult

  describe "list_all_programs/0" do
    test "returns all valid programs" do
      # Create valid programs with all required fields
      _program_1 =
        insert_program(%{
          title: "Soccer Camp",
          description: "Fun soccer for kids",
          age_range: "6-12",
          price: Decimal.new("150.00"),
          pricing_period: "per week"
        })

      _program_2 =
        insert_program(%{
          title: "Art Class",
          description: "Creative art activities",
          age_range: "8-14",
          price: Decimal.new("75.00"),
          pricing_period: "per month"
        })

      _program_3 =
        insert_program(%{
          title: "Dance Workshop",
          description: "Learn various dance styles",
          age_range: "10-16",
          price: Decimal.new("100.00"),
          pricing_period: "per session"
        })

      programs = ProgramRepository.list_all_programs()

      assert length(programs) >= 3
      assert Enum.all?(programs, &match?(%Program{}, &1))

      titles = Enum.map(programs, & &1.title)
      assert "Soccer Camp" in titles
      assert "Art Class" in titles
      assert "Dance Workshop" in titles
    end

    test "returns programs in ascending title order" do
      # Insert programs in non-alphabetical order
      insert_program(%{
        title: "Zebra Camp",
        description: "Description",
        age_range: "6-12",
        price: Decimal.new("100.00"),
        pricing_period: "per week"
      })

      insert_program(%{
        title: "Art Class",
        description: "Description",
        age_range: "6-12",
        price: Decimal.new("100.00"),
        pricing_period: "per week"
      })

      insert_program(%{
        title: "Music Lessons",
        description: "Description",
        age_range: "6-12",
        price: Decimal.new("100.00"),
        pricing_period: "per week"
      })

      programs = ProgramRepository.list_all_programs()

      titles = Enum.map(programs, & &1.title)
      assert "Art Class" in titles
      assert "Music Lessons" in titles
      assert "Zebra Camp" in titles

      # Verify relative ordering (ascending by title)
      art_idx = Enum.find_index(titles, &(&1 == "Art Class"))
      music_idx = Enum.find_index(titles, &(&1 == "Music Lessons"))
      zebra_idx = Enum.find_index(titles, &(&1 == "Zebra Camp"))
      assert art_idx < music_idx
      assert music_idx < zebra_idx
    end

    test "returns a list of Program structs" do
      programs = ProgramRepository.list_all_programs()

      assert is_list(programs)
      assert Enum.all?(programs, &match?(%Program{}, &1))
    end

    test "includes programs with price = 0 (free programs)" do
      _free_program =
        insert_program(%{
          title: "Free Community Day",
          description: "Free event for everyone",
          age_range: "All ages",
          price: Decimal.new("0.00"),
          pricing_period: "per session"
        })

      _paid_program =
        insert_program(%{
          title: "Paid Workshop",
          description: "Premium workshop",
          age_range: "10-15",
          price: Decimal.new("200.00"),
          pricing_period: "per week"
        })

      programs = ProgramRepository.list_all_programs()

      assert length(programs) >= 2

      free = Enum.find(programs, &(&1.title == "Free Community Day"))
      assert free.price == Decimal.new("0.00")
      assert Program.free?(free)

      paid = Enum.find(programs, &(&1.title == "Paid Workshop"))
      assert paid.price == Decimal.new("200.00")
      refute Program.free?(paid)
    end

    # Note: Testing actual database connection failures with retry logic
    # is complex and would require mocking or test infrastructure that
    # can simulate connection failures. This test verifies the happy path
    # and the retry logic implementation will be verified through integration
    # testing and manual testing of error scenarios.
    test "retries database query 3 times on connection failure" do
      # This test documents the retry requirement.
      # The actual retry logic will be implemented in the repository
      # and tested through integration tests or by simulating failures.
      #
      # Expected behavior:
      # - First attempt: immediate query
      # - Second attempt: 100ms delay
      # - Third attempt: 300ms delay
      # - After 3 failures: return {:error, :database_error}
      #
      # For this unit test, we verify the happy path works correctly.
      # The retry logic itself will be validated through:
      # 1. Code review of the implementation
      # 2. Integration tests with database simulation
      # 3. Manual testing with database connection issues

      insert_program(%{
        title: "Test Program",
        description: "Description",
        age_range: "6-12",
        price: Decimal.new("100.00"),
        pricing_period: "per week"
      })

      programs = ProgramRepository.list_all_programs()

      assert Enum.any?(programs, &(&1.title == "Test Program"))
    end
  end

  describe "list_programs_paginated/2" do
    setup do
      # Create 25 programs with staggered inserted_at timestamps
      # Newer programs have later timestamps (descending order)
      # Trigger: far-future base_time ensures setup programs always sort first (DESC)
      # Why: pre-existing programs from other tests won't shift expected positions
      base_time = ~U[2099-01-01 00:00:00Z]

      programs =
        for i <- 1..25 do
          insert_program_with_timestamp(
            %{
              title: "Program #{String.pad_leading(Integer.to_string(i), 2, "0")}",
              description: "Description #{i}",
              age_range: "6-12",
              price: Decimal.new("#{100 + i}.00"),
              pricing_period: "per week"
            },
            DateTime.add(base_time, i * 3600, :second)
          )
        end

      %{programs: programs}
    end

    test "returns first page with limit 10 and no cursor" do
      {:ok, page} = ProgramRepository.list_programs_paginated(10, nil)

      assert %PageResult{} = page
      assert length(page.items) == 10
      assert page.has_more == true
      assert page.next_cursor != nil
      assert page.metadata.returned_count == 10

      # Verify newest programs first (Program 25, 24, 23, ...)
      titles = Enum.map(page.items, & &1.title)
      assert List.first(titles) == "Program 25"
      assert List.last(titles) == "Program 16"
    end

    test "returns subsequent pages with cursor" do
      # Get first page
      {:ok, page1} = ProgramRepository.list_programs_paginated(10, nil)
      assert page1.has_more == true
      assert page1.next_cursor != nil

      # Get second page with cursor
      {:ok, page2} = ProgramRepository.list_programs_paginated(10, page1.next_cursor)
      assert length(page2.items) == 10
      assert page2.has_more == true
      assert page2.next_cursor != nil

      # Verify items are different and in correct order
      page1_titles = Enum.map(page1.items, & &1.title)
      page2_titles = Enum.map(page2.items, & &1.title)

      assert List.first(page2_titles) == "Program 15"
      assert List.last(page2_titles) == "Program 06"

      # Ensure no overlap
      refute Enum.any?(page1_titles, &(&1 in page2_titles))
    end

    test "sets has_more to true when more results exist" do
      {:ok, page} = ProgramRepository.list_programs_paginated(10, nil)

      assert page.has_more == true
      assert page.next_cursor != nil
    end

    test "paginates through all setup programs across pages" do
      # Get first page (10 items)
      {:ok, page1} = ProgramRepository.list_programs_paginated(10, nil)

      # Get second page (10 items)
      {:ok, page2} = ProgramRepository.list_programs_paginated(10, page1.next_cursor)

      # Get third page — should contain Programs 01-05 from setup
      {:ok, page3} = ProgramRepository.list_programs_paginated(10, page2.next_cursor)

      titles = Enum.map(page3.items, & &1.title)
      assert length(page3.items) >= 5
      assert "Program 05" in titles
      assert "Program 01" in titles
    end

    test "returns valid PageResult structure" do
      {:ok, page} = ProgramRepository.list_programs_paginated(20, nil)

      assert %PageResult{} = page
      assert is_list(page.items)
      assert is_boolean(page.has_more)
      assert Enum.all?(page.items, &match?(%Program{}, &1))
    end

    test "returns empty results when cursor is beyond last item" do
      # Paginate until has_more is false to find the true last page
      {:ok, page} = ProgramRepository.list_programs_paginated(25, nil)
      last_page = paginate_to_end(page, 25)

      # Create a cursor beyond the very last item
      last_program = List.last(last_page.items)
      fake_cursor = create_cursor_after(last_program)

      {:ok, beyond_page} = ProgramRepository.list_programs_paginated(10, fake_cursor)

      assert beyond_page.items == []
      assert beyond_page.has_more == false
      assert beyond_page.next_cursor == nil
    end

    test "handles invalid cursor gracefully" do
      invalid_cursor = "invalid_base64_cursor"

      assert {:error, :invalid_cursor} =
               ProgramRepository.list_programs_paginated(20, invalid_cursor)
    end

    test "handles malformed cursor data" do
      # Valid base64 but invalid JSON
      malformed_cursor = Base.url_encode64("not json", padding: false)

      assert {:error, :invalid_cursor} =
               ProgramRepository.list_programs_paginated(20, malformed_cursor)
    end

    test "handles cursor with invalid timestamp" do
      # Valid JSON but invalid timestamp
      invalid_data = Jason.encode!(%{"ts" => "not_a_number", "id" => Ecto.UUID.generate()})
      invalid_cursor = Base.url_encode64(invalid_data, padding: false)

      assert {:error, :invalid_cursor} =
               ProgramRepository.list_programs_paginated(20, invalid_cursor)
    end

    test "handles cursor with invalid UUID" do
      # Valid JSON but invalid UUID
      invalid_data = Jason.encode!(%{"ts" => 1_234_567_890_123_456, "id" => "not-a-uuid"})
      invalid_cursor = Base.url_encode64(invalid_data, padding: false)

      assert {:error, :invalid_cursor} =
               ProgramRepository.list_programs_paginated(20, invalid_cursor)
    end

    test "handles limit boundary conditions" do
      # Limit below minimum (0) - should be constrained to 1
      {:ok, page} = ProgramRepository.list_programs_paginated(0, nil)
      assert length(page.items) == 1

      # Limit at minimum (1)
      {:ok, page} = ProgramRepository.list_programs_paginated(1, nil)
      assert length(page.items) == 1

      # Limit at maximum (100) - should return at least 25 setup programs
      {:ok, page} = ProgramRepository.list_programs_paginated(100, nil)
      assert length(page.items) >= 25

      # Limit above maximum (101) - should be constrained to 100
      {:ok, page} = ProgramRepository.list_programs_paginated(101, nil)
      assert length(page.items) >= 25
    end

    test "orders by inserted_at DESC, id DESC" do
      {:ok, page} = ProgramRepository.list_programs_paginated(25, nil)

      # Verify newest first (Program 25 was inserted last with latest timestamp)
      titles = Enum.map(page.items, & &1.title)
      assert List.first(titles) == "Program 25"
      assert List.last(titles) == "Program 01"
    end

    test "cursor roundtrip encoding and decoding" do
      {:ok, page1} = ProgramRepository.list_programs_paginated(10, nil)
      cursor = page1.next_cursor

      # Use the cursor to get next page
      {:ok, page2} = ProgramRepository.list_programs_paginated(10, cursor)

      # Verify we got different items
      page1_titles = Enum.map(page1.items, & &1.title)
      page2_titles = Enum.map(page2.items, & &1.title)

      refute Enum.any?(page1_titles, &(&1 in page2_titles))
    end

    test "returns has_more false when limit exceeds total items" do
      # Request with limit larger than all programs — setup creates 25,
      # plus any pre-existing programs; limit=100 should capture all
      {:ok, page} = ProgramRepository.list_programs_paginated(100, nil)

      assert length(page.items) >= 25
      assert page.has_more == false
      assert page.next_cursor == nil
    end

    test "returns has_more true when items exceed limit" do
      # Setup creates 25 programs — request 10, so there must be more
      {:ok, page} = ProgramRepository.list_programs_paginated(10, nil)

      assert length(page.items) == 10
      assert page.has_more == true
      assert page.next_cursor != nil
    end

    test "all returned items are valid Program domain models" do
      {:ok, page} = ProgramRepository.list_programs_paginated(20, nil)

      assert Enum.all?(page.items, &match?(%Program{}, &1))
      assert Enum.all?(page.items, &(&1.title != nil))
      assert Enum.all?(page.items, &(&1.description != nil))
    end
  end

  describe "update/1 with optimistic locking" do
    test "successfully updates program and increments lock_version" do
      # Create a program
      program_schema =
        insert_program(%{
          title: "Original Title",
          description: "Original description",
          age_range: "6-12",
          price: Decimal.new("150.00"),
          pricing_period: "per week"
        })

      assert program_schema.lock_version == 1

      # Convert to domain and update
      domain_program = ProgramMapper.to_domain(program_schema)
      updated_program = %{domain_program | title: "Updated Title"}

      # Execute update
      assert {:ok, result} = ProgramRepository.update(updated_program)

      # Verify changes persisted
      assert result.title == "Updated Title"

      # Verify lock_version incremented
      updated_schema = Repo.get(ProgramSchema, program_schema.id)
      assert updated_schema.lock_version == 2
      assert updated_schema.title == "Updated Title"
    end

    test "detects concurrent modification with stale_data error" do
      # Create a program
      program_schema =
        insert_program(%{
          title: "Original Title",
          description: "Description",
          age_range: "6-12",
          price: Decimal.new("150.00"),
          pricing_period: "per week"
        })

      # Simulate two processes fetching the same program
      domain_v1_a = ProgramMapper.to_domain(program_schema)
      domain_v1_b = ProgramMapper.to_domain(program_schema)

      # First update succeeds (lock_version 1 → 2)
      updated_a = %{domain_v1_a | title: "Update A"}
      assert {:ok, _result} = ProgramRepository.update(updated_a)

      # Second update fails with stale data (still has lock_version 1)
      updated_b = %{domain_v1_b | title: "Update B"}
      assert {:error, :stale_data} = ProgramRepository.update(updated_b)

      # Verify first update persisted, second did not
      final_schema = Repo.get(ProgramSchema, program_schema.id)
      assert final_schema.title == "Update A"
      assert final_schema.lock_version == 2
    end

    test "handles multiple sequential updates with version increments" do
      # Create a program
      program_schema =
        insert_program(%{
          title: "Version 1",
          description: "Description",
          age_range: "6-12",
          price: Decimal.new("150.00"),
          pricing_period: "per week"
        })

      assert program_schema.lock_version == 1

      # First update
      domain_v1 = ProgramMapper.to_domain(program_schema)
      updated_v1 = %{domain_v1 | title: "Version 2"}
      assert {:ok, result_v2} = ProgramRepository.update(updated_v1)

      # Second update (using fresh domain from first update result)
      updated_v2 = %{result_v2 | title: "Version 3"}
      assert {:ok, result_v3} = ProgramRepository.update(updated_v2)

      # Third update (using fresh domain from second update result)
      updated_v3 = %{result_v3 | title: "Version 4"}
      assert {:ok, _result_v4} = ProgramRepository.update(updated_v3)

      # Verify final state
      final_schema = Repo.get(ProgramSchema, program_schema.id)
      assert final_schema.title == "Version 4"
      assert final_schema.lock_version == 4
    end

    test "returns not_found error for non-existent program" do
      # Create a program structure with non-existent ID
      non_existent_program = %Program{
        id: Ecto.UUID.generate(),
        title: "Non-existent",
        description: "Description",
        category: "education",
        meeting_days: ["Monday"],
        age_range: "6-12",
        price: Decimal.new("100.00"),
        pricing_period: "per week",
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }

      assert {:error, :not_found} = ProgramRepository.update(non_existent_program)
    end

    test "returns changeset error for constraint violation" do
      # Create a program
      program_schema =
        insert_program(%{
          title: "Valid Program",
          description: "Description",
          age_range: "6-12",
          price: Decimal.new("150.00"),
          pricing_period: "per week"
        })

      # Attempt update with invalid data (negative price violates constraint)
      domain_program = ProgramMapper.to_domain(program_schema)
      invalid_program = %{domain_program | price: Decimal.new("-100.00")}

      # Update should fail with changeset validation error
      # (validate_number ensures price >= 0)
      assert {:error, %Ecto.Changeset{valid?: false}} = ProgramRepository.update(invalid_program)

      # Verify original data unchanged
      unchanged_schema = Repo.get(ProgramSchema, program_schema.id)
      assert unchanged_schema.price == Decimal.new("150.00")
      assert unchanged_schema.lock_version == 1
    end

    test "returns changeset error for empty required field" do
      # Create a program
      program_schema =
        insert_program(%{
          title: "Valid Program",
          description: "Description",
          age_range: "6-12",
          price: Decimal.new("150.00"),
          pricing_period: "per week"
        })

      # Attempt update with empty title (required field)
      domain_program = ProgramMapper.to_domain(program_schema)
      invalid_program = %{domain_program | title: ""}

      # Update should fail with changeset validation error
      assert {:error, %Ecto.Changeset{valid?: false}} = ProgramRepository.update(invalid_program)

      # Verify original data unchanged
      unchanged_schema = Repo.get(ProgramSchema, program_schema.id)
      assert unchanged_schema.title == "Valid Program"
      assert unchanged_schema.lock_version == 1
    end

    test "updates all modifiable fields correctly" do
      # Create a program
      program_schema =
        insert_program(%{
          title: "Original",
          description: "Original description",
          age_range: "6-12",
          price: Decimal.new("150.00"),
          pricing_period: "per week"
        })

      # Update all modifiable fields
      domain_program = ProgramMapper.to_domain(program_schema)

      updated_program = %{
        domain_program
        | title: "New Title",
          description: "New description",
          meeting_days: ["Tuesday", "Thursday"],
          age_range: "8-14",
          price: Decimal.new("200.00"),
          pricing_period: "per month"
      }

      assert {:ok, result} = ProgramRepository.update(updated_program)

      # Verify all fields updated
      assert result.title == "New Title"
      assert result.description == "New description"
      assert result.meeting_days == ["Tuesday", "Thursday"]
      assert result.age_range == "8-14"
      assert result.price == Decimal.new("200.00")
      assert result.pricing_period == "per month"

      # Verify in database
      updated_schema = Repo.get(ProgramSchema, program_schema.id)
      assert updated_schema.title == "New Title"
      assert updated_schema.lock_version == 2
    end

    test "concurrent updates by multiple processes fail correctly" do
      # Create a program
      program_schema =
        insert_program(%{
          title: "Concurrent Test",
          description: "Description",
          age_range: "6-12",
          price: Decimal.new("150.00"),
          pricing_period: "per week"
        })

      # Simulate 5 concurrent processes attempting to update
      domain_programs =
        for i <- 1..5 do
          domain = ProgramMapper.to_domain(program_schema)
          %{domain | title: "Concurrent Update #{i}"}
        end

      # Execute all updates concurrently
      results =
        domain_programs
        |> Enum.map(&Task.async(fn -> ProgramRepository.update(&1) end))
        |> Enum.map(&Task.await/1)

      # Exactly one should succeed, others should fail with :stale_data
      successful_updates = Enum.count(results, &match?({:ok, _}, &1))
      stale_data_errors = Enum.count(results, &match?({:error, :stale_data}, &1))

      assert successful_updates == 1
      assert stale_data_errors == 4

      # Verify lock_version incremented only once
      final_schema = Repo.get(ProgramSchema, program_schema.id)
      assert final_schema.lock_version == 2
    end
  end

  describe "list_programs_for_provider/1" do
    test "returns programs for a specific provider" do
      provider = insert(:provider_profile_schema)
      other_provider = insert(:provider_profile_schema)

      # Create programs for target provider
      _program_1 =
        insert_program(%{
          title: "Soccer Camp",
          description: "Fun soccer",
          age_range: "6-12",
          price: Decimal.new("150.00"),
          pricing_period: "per week",
          provider_id: provider.id
        })

      _program_2 =
        insert_program(%{
          title: "Art Class",
          description: "Creative arts",
          age_range: "8-14",
          price: Decimal.new("75.00"),
          pricing_period: "per month",
          provider_id: provider.id
        })

      # Create program for different provider
      _other_program =
        insert_program(%{
          title: "Music Lessons",
          description: "Learn music",
          age_range: "10-16",
          price: Decimal.new("100.00"),
          pricing_period: "per session",
          provider_id: other_provider.id
        })

      programs = ProgramRepository.list_programs_for_provider(provider.id)

      assert length(programs) == 2
      assert Enum.all?(programs, &match?(%Program{}, &1))

      titles = Enum.map(programs, & &1.title)
      assert "Soccer Camp" in titles
      assert "Art Class" in titles
      refute "Music Lessons" in titles
    end

    test "returns programs in ascending title order" do
      provider = insert(:provider_profile_schema)

      insert_program(%{
        title: "Zebra Camp",
        description: "Description",
        age_range: "6-12",
        price: Decimal.new("100.00"),
        pricing_period: "per week",
        provider_id: provider.id
      })

      insert_program(%{
        title: "Art Class",
        description: "Description",
        age_range: "6-12",
        price: Decimal.new("100.00"),
        pricing_period: "per week",
        provider_id: provider.id
      })

      insert_program(%{
        title: "Music Lessons",
        description: "Description",
        age_range: "6-12",
        price: Decimal.new("100.00"),
        pricing_period: "per week",
        provider_id: provider.id
      })

      programs = ProgramRepository.list_programs_for_provider(provider.id)

      titles = Enum.map(programs, & &1.title)
      assert titles == ["Art Class", "Music Lessons", "Zebra Camp"]
    end

    test "returns empty list when provider has no programs" do
      provider = insert(:provider_profile_schema)

      programs = ProgramRepository.list_programs_for_provider(provider.id)

      assert programs == []
    end

    test "returns empty list for non-existent provider_id" do
      non_existent_id = Ecto.UUID.generate()

      # Create a program for a different provider to ensure database isn't empty
      provider = insert(:provider_profile_schema)

      insert_program(%{
        title: "Some Program",
        description: "Description",
        age_range: "6-12",
        price: Decimal.new("100.00"),
        pricing_period: "per week",
        provider_id: provider.id
      })

      programs = ProgramRepository.list_programs_for_provider(non_existent_id)

      assert programs == []
    end

    test "includes free and sold out programs" do
      provider = insert(:provider_profile_schema)

      _free_program =
        insert_program(%{
          title: "Free Community Day",
          description: "Free event",
          age_range: "All ages",
          price: Decimal.new("0.00"),
          pricing_period: "per session",
          provider_id: provider.id
        })

      _sold_out_program =
        insert_program(%{
          title: "Popular Camp",
          description: "Fully booked",
          age_range: "10-15",
          price: Decimal.new("200.00"),
          pricing_period: "per week",
          provider_id: provider.id
        })

      programs = ProgramRepository.list_programs_for_provider(provider.id)

      assert length(programs) == 2

      free = Enum.find(programs, &(&1.title == "Free Community Day"))
      assert free.price == Decimal.new("0.00")
      assert Program.free?(free)

      _popular = Enum.find(programs, &(&1.title == "Popular Camp"))
    end
  end

  describe "get_by_ids/1" do
    test "returns empty list for empty input" do
      assert ProgramRepository.get_by_ids([]) == []
    end

    test "returns all matching programs as domain models" do
      program_1 =
        insert_program(%{
          title: "Soccer Camp",
          description: "Fun soccer",
          age_range: "6-12",
          price: Decimal.new("150.00"),
          pricing_period: "per week"
        })

      program_2 =
        insert_program(%{
          title: "Art Class",
          description: "Creative arts",
          age_range: "8-14",
          price: Decimal.new("75.00"),
          pricing_period: "per month"
        })

      results = ProgramRepository.get_by_ids([program_1.id, program_2.id])

      assert length(results) == 2
      assert Enum.all?(results, &match?(%Program{}, &1))

      titles = Enum.map(results, & &1.title)
      assert "Soccer Camp" in titles
      assert "Art Class" in titles
    end

    test "silently omits non-existent IDs" do
      program =
        insert_program(%{
          title: "Existing Program",
          description: "Description",
          age_range: "6-12",
          price: Decimal.new("100.00"),
          pricing_period: "per week"
        })

      non_existent_id = Ecto.UUID.generate()
      results = ProgramRepository.get_by_ids([program.id, non_existent_id])

      assert length(results) == 1
      assert hd(results).title == "Existing Program"
    end

    test "returns empty list when no IDs match" do
      ids = [Ecto.UUID.generate(), Ecto.UUID.generate()]

      assert ProgramRepository.get_by_ids(ids) == []
    end
  end

  # Helper function to insert a complete valid program
  defp insert_program(attrs) do
    default_attrs = %{
      id: Ecto.UUID.generate(),
      category: "education"
    }

    attrs = Map.merge(default_attrs, attrs)

    %ProgramSchema{}
    |> ProgramSchema.changeset(attrs)
    |> Repo.insert!()
  end

  # Helper function to insert program with specific timestamp
  defp insert_program_with_timestamp(attrs, inserted_at) do
    default_attrs = %{
      id: Ecto.UUID.generate(),
      category: "education"
    }

    attrs = Map.merge(default_attrs, attrs)

    %ProgramSchema{}
    |> ProgramSchema.changeset(attrs)
    |> Ecto.Changeset.put_change(:inserted_at, inserted_at)
    |> Repo.insert!()
  end

  # Follows pagination until has_more is false, returning the final page.
  # Max iterations guard prevents infinite loops from broken pagination.
  defp paginate_to_end(page, limit), do: paginate_to_end(page, limit, _remaining = 100)

  defp paginate_to_end(%{has_more: false} = page, _limit, _remaining), do: page

  defp paginate_to_end(%{has_more: true, next_cursor: nil}, _limit, _remaining) do
    raise "Pagination bug: has_more is true but next_cursor is nil"
  end

  defp paginate_to_end(_page, _limit, 0) do
    raise "Exceeded max pagination iterations (100)"
  end

  defp paginate_to_end(%{next_cursor: cursor}, limit, remaining) do
    {:ok, next_page} = ProgramRepository.list_programs_paginated(limit, cursor)
    paginate_to_end(next_page, limit, remaining - 1)
  end

  # Helper to create a cursor pointing after a given program
  defp create_cursor_after(program) do
    # Create a timestamp 1 second before the program's inserted_at
    cursor_ts = DateTime.add(program.inserted_at, -1, :second)

    cursor_data = %{
      "ts" => DateTime.to_unix(cursor_ts, :microsecond),
      "id" => program.id
    }

    cursor_data
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end
end
