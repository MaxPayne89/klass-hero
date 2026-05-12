defmodule KlassHero.ProgramCatalog.Domain.Models.ProgramTest do
  @moduledoc """
  Tests for the Program domain model.

  Note: Full field validation (length limits, category whitelist, etc.) is handled
  by the Ecto schema layer. The domain model provides simplified runtime invariant
  checks via valid?/1 and business logic helpers like free?/1.
  """

  use ExUnit.Case, async: true

  alias KlassHero.ProgramCatalog.Domain.Models.{Instructor, Program, RegistrationPeriod}

  # Helper to build valid program attrs
  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        id: "550e8400-e29b-41d4-a716-446655440000",
        title: "Summer Soccer Camp",
        description: "Fun soccer activities for kids",
        category: "sports",
        age_range: "6-10 years",
        price: Decimal.new("150.00"),
        pricing_period: "per week",
        meeting_days: [],
        registration_period: %RegistrationPeriod{}
      },
      overrides
    )
  end

  describe "new/1 constructor" do
    test "creates a program from valid attributes" do
      attrs = valid_attrs()

      assert {:ok, program} = Program.new(attrs)
      assert program.id == "550e8400-e29b-41d4-a716-446655440000"
      assert program.title == "Summer Soccer Camp"
      assert program.description == "Fun soccer activities for kids"
      assert program.meeting_days == []
      assert program.age_range == "6-10 years"
      assert Decimal.equal?(program.price, Decimal.new("150.00"))
      assert program.pricing_period == "per week"
    end

    test "creates a free program (price = 0)" do
      attrs = valid_attrs(%{price: Decimal.new("0"), pricing_period: "free event"})

      assert {:ok, program} = Program.new(attrs)
      assert Decimal.equal?(program.price, Decimal.new("0"))
      assert Program.free?(program)
    end

    test "includes optional fields when present" do
      now = DateTime.utc_now()

      attrs =
        valid_attrs(%{
          lock_version: 1,
          inserted_at: now,
          updated_at: now
        })

      assert {:ok, program} = Program.new(attrs)
      assert program.lock_version == 1
      assert program.inserted_at == now
      assert program.updated_at == now
    end
  end

  describe "new!/1 constructor" do
    test "creates a program from valid attributes" do
      attrs = valid_attrs()

      program = Program.new!(attrs)

      assert %Program{} = program
      assert program.title == "Summer Soccer Camp"
    end

    test "raises on missing required keys" do
      attrs = %{title: "Test"}

      assert_raise ArgumentError, fn ->
        Program.new!(attrs)
      end
    end
  end

  describe "valid?/1" do
    test "returns true for a program with all required fields valid" do
      program = %Program{
        id: "550e8400-e29b-41d4-a716-446655440000",
        title: "Summer Soccer Camp",
        description: "Fun soccer activities for kids",
        category: "sports",
        age_range: "6-10 years",
        price: Decimal.new("150.00"),
        pricing_period: "per week"
      }

      assert Program.valid?(program)
    end

    test "returns true for a free program (price = 0)" do
      program = %Program{
        id: "550e8400-e29b-41d4-a716-446655440002",
        title: "Community Sports Day",
        description: "Free sports activities for all",
        category: "education",
        age_range: "5-15 years",
        price: Decimal.new("0"),
        pricing_period: "free event"
      }

      assert Program.valid?(program)
    end

    test "returns false when title is empty string" do
      program = %Program{
        id: "550e8400-e29b-41d4-a716-446655440004",
        title: "",
        description: "Valid description",
        category: "education",
        age_range: "6-10 years",
        price: Decimal.new("100.00"),
        pricing_period: "per week"
      }

      refute Program.valid?(program)
    end

    test "returns false when title is only whitespace" do
      program = %Program{
        id: "550e8400-e29b-41d4-a716-446655440005",
        title: "   ",
        description: "Valid description",
        category: "education",
        age_range: "6-10 years",
        price: Decimal.new("100.00"),
        pricing_period: "per week"
      }

      refute Program.valid?(program)
    end

    test "returns false when description is empty string" do
      program = %Program{
        id: "550e8400-e29b-41d4-a716-446655440008",
        title: "Valid Title",
        description: "",
        category: "education",
        age_range: "6-10 years",
        price: Decimal.new("100.00"),
        pricing_period: "per week"
      }

      refute Program.valid?(program)
    end

    test "returns false when description is only whitespace" do
      program = %Program{
        id: "550e8400-e29b-41d4-a716-446655440009",
        title: "Valid Title",
        description: "   ",
        category: "education",
        age_range: "6-10 years",
        price: Decimal.new("100.00"),
        pricing_period: "per week"
      }

      refute Program.valid?(program)
    end

    test "returns false when price is negative" do
      program = %Program{
        id: "550e8400-e29b-41d4-a716-446655440012",
        title: "Valid Title",
        description: "Valid description",
        category: "education",
        age_range: "6-10 years",
        price: Decimal.new("-10.00"),
        pricing_period: "per week"
      }

      refute Program.valid?(program)
    end
  end

  describe "free?/1" do
    test "returns true when price is 0" do
      program = %Program{
        id: "550e8400-e29b-41d4-a716-446655440021",
        title: "Free Program",
        description: "This program is free",
        category: "education",
        age_range: "6-10 years",
        price: Decimal.new("0"),
        pricing_period: "free"
      }

      assert Program.free?(program)
    end

    test "returns true when price is 0.00" do
      program = %Program{
        id: "550e8400-e29b-41d4-a716-446655440022",
        title: "Free Event",
        description: "Free community event",
        category: "education",
        age_range: "5-15 years",
        price: Decimal.new("0.00"),
        pricing_period: "free"
      }

      assert Program.free?(program)
    end

    test "returns false when price is greater than 0" do
      program = %Program{
        id: "550e8400-e29b-41d4-a716-446655440023",
        title: "Paid Program",
        description: "This program has a fee",
        category: "education",
        age_range: "6-10 years",
        price: Decimal.new("0.01"),
        pricing_period: "per session"
      }

      refute Program.free?(program)
    end

    test "returns false when price is a typical positive value" do
      program = %Program{
        id: "550e8400-e29b-41d4-a716-446655440024",
        title: "Premium Program",
        description: "Premium activities",
        category: "education",
        age_range: "6-10 years",
        price: Decimal.new("150.00"),
        pricing_period: "per week"
      }

      refute Program.free?(program)
    end
  end

  describe "registration_open?/1" do
    test "returns true for always-open registration (both dates nil)" do
      {:ok, program} = Program.new(valid_attrs())
      assert Program.registration_open?(program)
    end

    test "returns true when today is within the registration window" do
      rp = %RegistrationPeriod{
        start_date: Date.add(Date.utc_today(), -5),
        end_date: Date.add(Date.utc_today(), 5)
      }

      {:ok, program} = Program.new(valid_attrs(%{registration_period: rp}))
      assert Program.registration_open?(program)
    end

    test "returns false for upcoming registration" do
      rp = %RegistrationPeriod{
        start_date: Date.add(Date.utc_today(), 10),
        end_date: Date.add(Date.utc_today(), 20)
      }

      {:ok, program} = Program.new(valid_attrs(%{registration_period: rp}))
      refute Program.registration_open?(program)
    end

    test "returns false for closed registration" do
      rp = %RegistrationPeriod{
        start_date: Date.add(Date.utc_today(), -20),
        end_date: Date.add(Date.utc_today(), -5)
      }

      {:ok, program} = Program.new(valid_attrs(%{registration_period: rp}))
      refute Program.registration_open?(program)
    end
  end

  describe "registration_status/1" do
    test "returns :always_open when both dates nil" do
      {:ok, program} = Program.new(valid_attrs())
      assert Program.registration_status(program) == :always_open
    end

    test "returns :open when within window" do
      rp = %RegistrationPeriod{
        start_date: Date.add(Date.utc_today(), -5),
        end_date: Date.add(Date.utc_today(), 5)
      }

      {:ok, program} = Program.new(valid_attrs(%{registration_period: rp}))
      assert Program.registration_status(program) == :open
    end

    test "returns :upcoming when before start" do
      rp = %RegistrationPeriod{
        start_date: Date.add(Date.utc_today(), 10),
        end_date: Date.add(Date.utc_today(), 20)
      }

      {:ok, program} = Program.new(valid_attrs(%{registration_period: rp}))
      assert Program.registration_status(program) == :upcoming
    end

    test "returns :closed when after end" do
      rp = %RegistrationPeriod{
        start_date: Date.add(Date.utc_today(), -20),
        end_date: Date.add(Date.utc_today(), -5)
      }

      {:ok, program} = Program.new(valid_attrs(%{registration_period: rp}))
      assert Program.registration_status(program) == :closed
    end
  end

  describe "new/1 with relaxed enforce_keys" do
    @minimal_attrs %{
      id: "550e8400-e29b-41d4-a716-446655440000",
      provider_id: "660e8400-e29b-41d4-a716-446655440001",
      title: "Art Adventures",
      description: "Creative art program for kids",
      category: "arts",
      price: Decimal.new("50.00")
    }

    test "creates program with only required fields" do
      assert {:ok, program} = Program.new(@minimal_attrs)
      assert program.title == "Art Adventures"
      assert program.meeting_days == []
      assert program.age_range == nil
    end

    test "creates program with location" do
      attrs = Map.put(@minimal_attrs, :location, "Community Center, Main St")
      assert {:ok, program} = Program.new(attrs)
      assert program.location == "Community Center, Main St"
    end

    test "creates program with cover_image_url" do
      attrs = Map.put(@minimal_attrs, :cover_image_url, "https://example.com/cover.jpg")
      assert {:ok, program} = Program.new(attrs)
      assert program.cover_image_url == "https://example.com/cover.jpg"
    end

    test "creates program with instructor" do
      {:ok, instructor} = Instructor.new(%{id: "abc", name: "Mike J", headshot_url: nil})
      attrs = Map.put(@minimal_attrs, :instructor, instructor)
      assert {:ok, program} = Program.new(attrs)
      assert program.instructor.name == "Mike J"
    end
  end

  describe "create/1" do
    test "creates program from valid attrs" do
      attrs = %{
        title: "Summer Soccer Camp",
        description: "Fun soccer activities for kids",
        category: "sports",
        price: Decimal.new("150.00"),
        provider_id: "660e8400-e29b-41d4-a716-446655440001"
      }

      assert {:ok, program} = Program.create(attrs)
      assert program.title == "Summer Soccer Camp"
      assert program.category == "sports"
      assert program.id == nil
    end

    test "creates program with optional fields" do
      attrs = %{
        title: "Art Adventures",
        description: "Creative art program",
        category: "arts",
        price: Decimal.new("50.00"),
        provider_id: "660e8400-e29b-41d4-a716-446655440001",
        meeting_days: ["Monday", "Wednesday"],
        meeting_start_time: ~T[15:00:00],
        meeting_end_time: ~T[17:00:00],
        age_range: "6-10 years",
        pricing_period: "per week",
        location: "Community Center"
      }

      assert {:ok, program} = Program.create(attrs)
      assert program.meeting_days == ["Monday", "Wednesday"]
      assert program.meeting_start_time == ~T[15:00:00]
      assert program.location == "Community Center"
    end

    test "creates program with valid instructor data" do
      attrs = %{
        title: "Coached Program",
        description: "Has instructor",
        category: "sports",
        price: Decimal.new("100.00"),
        provider_id: "660e8400-e29b-41d4-a716-446655440001",
        instructor: %{
          id: "abc-123",
          name: "Jane Coach",
          headshot_url: "https://example.com/photo.jpg"
        }
      }

      assert {:ok, program} = Program.create(attrs)
      assert %Instructor{} = program.instructor
      assert program.instructor.name == "Jane Coach"
    end

    test "creates program without instructor" do
      attrs = %{
        title: "No Coach",
        description: "Self-directed program",
        category: "arts",
        price: Decimal.new("50.00"),
        provider_id: "660e8400-e29b-41d4-a716-446655440001"
      }

      assert {:ok, program} = Program.create(attrs)
      assert program.instructor == nil
    end

    test "rejects empty title" do
      attrs = %{
        title: "",
        description: "Valid description",
        category: "sports",
        price: Decimal.new("100.00"),
        provider_id: "660e8400-e29b-41d4-a716-446655440001"
      }

      assert {:error, errors} = Program.create(attrs)
      assert is_list(errors)
      assert Enum.any?(errors, &String.contains?(&1, "title"))
    end

    test "rejects whitespace-only title" do
      attrs = %{
        title: "   ",
        description: "Valid",
        category: "sports",
        price: Decimal.new("100.00"),
        provider_id: "660e8400-e29b-41d4-a716-446655440001"
      }

      assert {:error, errors} = Program.create(attrs)
      assert Enum.any?(errors, &String.contains?(&1, "title"))
    end

    test "rejects missing title" do
      attrs = %{
        description: "Valid",
        category: "sports",
        price: Decimal.new("100.00"),
        provider_id: "660e8400-e29b-41d4-a716-446655440001"
      }

      assert {:error, errors} = Program.create(attrs)
      assert Enum.any?(errors, &String.contains?(&1, "title"))
    end

    test "rejects empty description" do
      attrs = %{
        title: "Valid Title",
        description: "",
        category: "sports",
        price: Decimal.new("100.00"),
        provider_id: "660e8400-e29b-41d4-a716-446655440001"
      }

      assert {:error, errors} = Program.create(attrs)
      assert Enum.any?(errors, &String.contains?(&1, "description"))
    end

    test "rejects invalid category" do
      attrs = %{
        title: "Valid Title",
        description: "Valid description",
        category: "invalid_category",
        price: Decimal.new("100.00"),
        provider_id: "660e8400-e29b-41d4-a716-446655440001"
      }

      assert {:error, errors} = Program.create(attrs)
      assert Enum.any?(errors, &String.contains?(&1, "category"))
    end

    test "rejects missing category" do
      attrs = %{
        title: "Valid Title",
        description: "Valid description",
        price: Decimal.new("100.00"),
        provider_id: "660e8400-e29b-41d4-a716-446655440001"
      }

      assert {:error, errors} = Program.create(attrs)
      assert Enum.any?(errors, &String.contains?(&1, "category"))
    end

    test "rejects negative price" do
      attrs = %{
        title: "Valid Title",
        description: "Valid description",
        category: "sports",
        price: Decimal.new("-10.00"),
        provider_id: "660e8400-e29b-41d4-a716-446655440001"
      }

      assert {:error, errors} = Program.create(attrs)
      assert Enum.any?(errors, &String.contains?(&1, "price"))
    end

    test "rejects missing provider_id" do
      attrs = %{
        title: "Valid Title",
        description: "Valid description",
        category: "sports",
        price: Decimal.new("100.00")
      }

      assert {:error, errors} = Program.create(attrs)
      assert Enum.any?(errors, &String.contains?(&1, "rovider"))
    end

    test "rejects invalid instructor data" do
      attrs = %{
        title: "Valid",
        description: "Valid",
        category: "sports",
        price: Decimal.new("100.00"),
        provider_id: "660e8400-e29b-41d4-a716-446655440001",
        instructor: %{id: "", name: "Jane"}
      }

      assert {:error, errors} = Program.create(attrs)
      assert Enum.any?(errors, &String.contains?(&1, "nstructor"))
    end

    test "builds RegistrationPeriod from flat registration date attrs" do
      attrs = %{
        title: "Camp with Registration Window",
        description: "Has a registration period",
        category: "sports",
        price: Decimal.new("100.00"),
        provider_id: "660e8400-e29b-41d4-a716-446655440001",
        registration_start_date: ~D[2026-01-15],
        registration_end_date: ~D[2026-02-15]
      }

      assert {:ok, program} = Program.create(attrs)
      assert %RegistrationPeriod{} = program.registration_period
      assert program.registration_period.start_date == ~D[2026-01-15]
      assert program.registration_period.end_date == ~D[2026-02-15]
    end

    test "defaults to empty RegistrationPeriod when no registration dates provided" do
      attrs = %{
        title: "No Registration Window",
        description: "Always open registration",
        category: "arts",
        price: Decimal.new("50.00"),
        provider_id: "660e8400-e29b-41d4-a716-446655440001"
      }

      assert {:ok, program} = Program.create(attrs)
      assert %RegistrationPeriod{start_date: nil, end_date: nil} = program.registration_period
    end

    test "rejects invalid registration period (start after end)" do
      attrs = %{
        title: "Bad Registration Window",
        description: "Invalid registration dates",
        category: "sports",
        price: Decimal.new("100.00"),
        provider_id: "660e8400-e29b-41d4-a716-446655440001",
        registration_start_date: ~D[2026-03-01],
        registration_end_date: ~D[2026-02-01]
      }

      assert {:error, errors} = Program.create(attrs)
      assert Enum.any?(errors, &String.contains?(&1, "registration"))
    end

    test "accepts price of zero (free programs)" do
      attrs = %{
        title: "Free Event",
        description: "A free community event",
        category: "education",
        price: Decimal.new("0"),
        provider_id: "660e8400-e29b-41d4-a716-446655440001"
      }

      assert {:ok, program} = Program.create(attrs)
      assert Program.free?(program)
    end
  end

  describe "apply_changes/2" do
    defp existing_program do
      %Program{
        id: "550e8400-e29b-41d4-a716-446655440000",
        title: "Original Title",
        description: "Original description",
        category: "sports",
        price: Decimal.new("150.00"),
        provider_id: "660e8400-e29b-41d4-a716-446655440001",
        lock_version: 1
      }
    end

    test "updates title" do
      program = existing_program()
      assert {:ok, updated} = Program.apply_changes(program, %{title: "New Title"})
      assert updated.title == "New Title"
      assert updated.description == "Original description"
    end

    test "updates multiple fields" do
      program = existing_program()

      assert {:ok, updated} =
               Program.apply_changes(program, %{
                 title: "Updated",
                 price: Decimal.new("200.00")
               })

      assert updated.title == "Updated"
      assert updated.price == Decimal.new("200.00")
    end

    test "preserves fields not in changes" do
      program = existing_program()
      assert {:ok, updated} = Program.apply_changes(program, %{title: "New"})
      assert updated.category == "sports"
      assert updated.provider_id == "660e8400-e29b-41d4-a716-446655440001"
      assert updated.lock_version == 1
    end

    test "adds instructor to program without one" do
      program = existing_program()

      assert {:ok, updated} =
               Program.apply_changes(program, %{
                 instructor: %{id: "abc-123", name: "Jane Coach"}
               })

      assert %Instructor{} = updated.instructor
      assert updated.instructor.name == "Jane Coach"
    end

    test "removes instructor when set to nil" do
      {:ok, instructor} = Instructor.new(%{id: "abc-123", name: "Jane"})
      program = %{existing_program() | instructor: instructor}

      assert {:ok, updated} = Program.apply_changes(program, %{instructor: nil})
      assert updated.instructor == nil
    end

    test "rejects invalid changes (empty title)" do
      program = existing_program()
      assert {:error, errors} = Program.apply_changes(program, %{title: ""})
      assert Enum.any?(errors, &String.contains?(&1, "title"))
    end

    test "rejects invalid changes (negative price)" do
      program = existing_program()
      assert {:error, errors} = Program.apply_changes(program, %{price: Decimal.new("-5.00")})
      assert Enum.any?(errors, &String.contains?(&1, "price"))
    end

    test "rejects invalid category change" do
      program = existing_program()
      assert {:error, errors} = Program.apply_changes(program, %{category: "invalid"})
      assert Enum.any?(errors, &String.contains?(&1, "category"))
    end

    test "returns unchanged program with empty changes map" do
      program = existing_program()
      assert {:ok, updated} = Program.apply_changes(program, %{})
      assert updated.title == program.title
      assert updated.description == program.description
      assert updated.category == program.category
      assert updated.price == program.price
      assert updated.instructor == program.instructor
    end

    test "rejects invalid instructor data in changes" do
      program = existing_program()

      assert {:error, errors} =
               Program.apply_changes(program, %{instructor: %{id: "", name: ""}})

      assert Enum.any?(errors, &String.contains?(&1, "nstructor"))
    end

    test "updates registration_period field" do
      program = existing_program()
      new_rp = %RegistrationPeriod{start_date: ~D[2026-03-01], end_date: ~D[2026-04-01]}

      assert {:ok, updated} = Program.apply_changes(program, %{registration_period: new_rp})
      assert updated.registration_period == new_rp
    end

    test "rejects invalid registration_period (start after end)" do
      program = existing_program()

      invalid_rp = %RegistrationPeriod{
        start_date: ~D[2026-04-01],
        end_date: ~D[2026-03-01]
      }

      assert {:error, errors} =
               Program.apply_changes(program, %{registration_period: invalid_rp})

      assert Enum.any?(errors, &String.contains?(&1, "registration"))
    end

    test "accepts valid registration_period update" do
      program = existing_program()

      valid_rp = %RegistrationPeriod{
        start_date: ~D[2026-03-01],
        end_date: ~D[2026-04-01]
      }

      assert {:ok, updated} = Program.apply_changes(program, %{registration_period: valid_rp})
      assert updated.registration_period == valid_rp
    end

    test "ignores provider_id in changes (immutable field)" do
      program = existing_program()
      original_provider_id = program.provider_id

      assert {:ok, updated} =
               Program.apply_changes(program, %{
                 provider_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
                 title: "Updated Title"
               })

      assert updated.provider_id == original_provider_id
      assert updated.title == "Updated Title"
    end
  end

  describe "scheduling validation in create/1" do
    defp scheduling_attrs(overrides \\ %{}) do
      Map.merge(
        %{
          title: "Scheduled Program",
          description: "Has a schedule",
          category: "sports",
          price: Decimal.new("100.00"),
          provider_id: "660e8400-e29b-41d4-a716-446655440001"
        },
        overrides
      )
    end

    test "accepts valid scheduling fields" do
      attrs =
        scheduling_attrs(%{
          meeting_days: ["Monday", "Wednesday"],
          meeting_start_time: ~T[16:00:00],
          meeting_end_time: ~T[17:30:00],
          start_date: ~D[2026-03-01],
          end_date: ~D[2026-06-30]
        })

      assert {:ok, program} = Program.create(attrs)
      assert program.meeting_days == ["Monday", "Wednesday"]
      assert program.meeting_start_time == ~T[16:00:00]
      assert program.meeting_end_time == ~T[17:30:00]
      assert program.start_date == ~D[2026-03-01]
    end

    test "accepts empty scheduling fields" do
      attrs = scheduling_attrs()
      assert {:ok, program} = Program.create(attrs)
      assert program.meeting_days == []
      assert program.meeting_start_time == nil
      assert program.meeting_end_time == nil
      assert program.start_date == nil
    end

    test "rejects invalid weekday names" do
      attrs = scheduling_attrs(%{meeting_days: ["Monday", "Funday"]})
      assert {:error, errors} = Program.create(attrs)
      assert Enum.any?(errors, &String.contains?(&1, "meeting_days"))
    end

    test "rejects start_time without end_time" do
      attrs = scheduling_attrs(%{meeting_start_time: ~T[16:00:00]})
      assert {:error, errors} = Program.create(attrs)
      assert Enum.any?(errors, &String.contains?(&1, "time"))
    end

    test "rejects end_time without start_time" do
      attrs = scheduling_attrs(%{meeting_end_time: ~T[17:00:00]})
      assert {:error, errors} = Program.create(attrs)
      assert Enum.any?(errors, &String.contains?(&1, "time"))
    end

    test "rejects end_time not after start_time" do
      attrs =
        scheduling_attrs(%{
          meeting_start_time: ~T[17:00:00],
          meeting_end_time: ~T[16:00:00]
        })

      assert {:error, errors} = Program.create(attrs)
      assert Enum.any?(errors, &String.contains?(&1, "time"))
    end

    test "rejects equal start and end times" do
      attrs =
        scheduling_attrs(%{
          meeting_start_time: ~T[16:00:00],
          meeting_end_time: ~T[16:00:00]
        })

      assert {:error, errors} = Program.create(attrs)
      assert Enum.any?(errors, &String.contains?(&1, "time"))
    end

    test "rejects start_date strictly after end_date" do
      attrs =
        scheduling_attrs(%{
          start_date: ~D[2026-06-30],
          end_date: ~D[2026-03-01]
        })

      assert {:error, errors} = Program.create(attrs)
      assert "start_date must be on or before end_date" in errors
    end

    test "accepts equal start_date and end_date (single-day workshop)" do
      attrs =
        scheduling_attrs(%{
          start_date: ~D[2026-03-15],
          end_date: ~D[2026-03-15]
        })

      assert {:ok, %Program{start_date: ~D[2026-03-15], end_date: ~D[2026-03-15]}} =
               Program.create(attrs)
    end

    test "rejects invalid date types" do
      attrs = scheduling_attrs(%{start_date: "2026-03-01", end_date: "2026-06-30"})

      assert {:error, errors} = Program.create(attrs)
      assert Enum.any?(errors, &String.contains?(&1, "invalid type"))
    end
  end

  describe "origin field" do
    test "create/1 defaults origin to :self_posted" do
      attrs = %{
        provider_id: "550e8400-e29b-41d4-a716-446655440000",
        title: "Test Program",
        description: "A test program",
        category: "sports",
        price: Decimal.new("50.00")
      }

      assert {:ok, program} = Program.create(attrs)
      assert program.origin == :self_posted
    end

    test "new/1 preserves origin from trusted data" do
      attrs = valid_attrs(%{origin: :business_assigned})

      assert {:ok, program} = Program.new(attrs)
      assert program.origin == :business_assigned
    end
  end

  describe "apply_changes/2 scheduling" do
    test "updates scheduling fields" do
      program = existing_program()

      changes = %{
        meeting_days: ["Tuesday", "Thursday"],
        meeting_start_time: ~T[15:00:00],
        meeting_end_time: ~T[16:30:00],
        start_date: ~D[2026-04-01]
      }

      assert {:ok, updated} = Program.apply_changes(program, changes)
      assert updated.meeting_days == ["Tuesday", "Thursday"]
      assert updated.meeting_start_time == ~T[15:00:00]
    end

    test "rejects invalid scheduling changes" do
      program = existing_program()

      changes = %{
        meeting_start_time: ~T[17:00:00],
        meeting_end_time: ~T[16:00:00]
      }

      assert {:error, errors} = Program.apply_changes(program, changes)
      assert Enum.any?(errors, &String.contains?(&1, "time"))
    end
  end

  describe "valid?/1 with relaxed fields" do
    test "valid with minimal fields" do
      {:ok, program} =
        Program.new(%{
          id: "550e8400-e29b-41d4-a716-446655440000",
          provider_id: "660e8400-e29b-41d4-a716-446655440001",
          title: "Art Adventures",
          description: "Creative art program for kids",
          category: "arts",
          price: Decimal.new("50.00")
        })

      assert Program.valid?(program)
    end

    test "invalid with empty title" do
      {:ok, program} =
        Program.new(%{
          id: "550e8400-e29b-41d4-a716-446655440000",
          provider_id: "660e8400-e29b-41d4-a716-446655440001",
          title: "Art Adventures",
          description: "Creative art program for kids",
          category: "arts",
          price: Decimal.new("50.00")
        })

      program = %{program | title: ""}
      refute Program.valid?(program)
    end
  end
end
