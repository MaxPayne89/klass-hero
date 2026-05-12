defmodule KlassHero.ProgramCatalog.Adapters.Driven.Persistence.Schemas.ProgramSchemaTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.ProgramCatalog.Adapters.Driven.Persistence.Schemas.ProgramSchema

  describe "changeset/2" do
    defp valid_attrs(overrides \\ %{}) do
      Map.merge(
        %{
          title: "Summer Soccer Camp",
          description: "Fun soccer activities for kids",
          category: "education",
          age_range: "6-12",
          price: Decimal.new("150.00"),
          pricing_period: "per week"
        },
        overrides
      )
    end

    test "valid changeset with all required fields" do
      changeset = ProgramSchema.changeset(%ProgramSchema{}, valid_attrs())

      assert changeset.valid?
      assert changeset.errors == []
    end

    test "valid changeset with minimum required fields" do
      changeset = ProgramSchema.changeset(%ProgramSchema{}, valid_attrs())

      assert changeset.valid?
      assert changeset.errors == []
    end

    test "valid changeset with price = 0 (free program)" do
      changeset =
        ProgramSchema.changeset(%ProgramSchema{}, valid_attrs(%{price: Decimal.new("0.00")}))

      assert changeset.valid?
      assert get_change(changeset, :price) == Decimal.new("0.00")
    end

    test "invalid changeset when title is missing" do
      changeset = ProgramSchema.changeset(%ProgramSchema{}, Map.delete(valid_attrs(), :title))

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).title
    end

    test "invalid changeset when description is missing" do
      changeset =
        ProgramSchema.changeset(%ProgramSchema{}, Map.delete(valid_attrs(), :description))

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).description
    end

    test "invalid changeset when age_range is missing" do
      changeset = ProgramSchema.changeset(%ProgramSchema{}, Map.delete(valid_attrs(), :age_range))

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).age_range
    end

    test "invalid changeset when price is missing" do
      changeset = ProgramSchema.changeset(%ProgramSchema{}, Map.delete(valid_attrs(), :price))

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).price
    end

    test "invalid changeset when pricing_period is missing" do
      changeset =
        ProgramSchema.changeset(%ProgramSchema{}, Map.delete(valid_attrs(), :pricing_period))

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).pricing_period
    end

    test "invalid changeset when title exceeds 100 characters" do
      changeset =
        ProgramSchema.changeset(
          %ProgramSchema{},
          valid_attrs(%{title: String.duplicate("a", 101)})
        )

      refute changeset.valid?
      assert "should be at most 100 character(s)" in errors_on(changeset).title
    end

    test "invalid changeset when description exceeds 500 characters" do
      changeset =
        ProgramSchema.changeset(
          %ProgramSchema{},
          valid_attrs(%{description: String.duplicate("a", 501)})
        )

      refute changeset.valid?
      assert "should be at most 500 character(s)" in errors_on(changeset).description
    end

    test "invalid changeset when price is negative" do
      changeset =
        ProgramSchema.changeset(%ProgramSchema{}, valid_attrs(%{price: Decimal.new("-10.00")}))

      refute changeset.valid?
      assert "must be greater than or equal to 0" in errors_on(changeset).price
    end

    test "title at exactly 100 characters is valid" do
      changeset =
        ProgramSchema.changeset(
          %ProgramSchema{},
          valid_attrs(%{title: String.duplicate("a", 100)})
        )

      assert changeset.valid?
    end

    test "description at exactly 500 characters is valid" do
      changeset =
        ProgramSchema.changeset(
          %ProgramSchema{},
          valid_attrs(%{description: String.duplicate("a", 500)})
        )

      assert changeset.valid?
    end
  end

  describe "changeset/2 scheduling validations" do
    defp valid_changeset_attrs(overrides) do
      Map.merge(
        %{
          title: "Test Program",
          description: "A test program",
          category: "education",
          age_range: "6-12",
          price: Decimal.new("100.00"),
          pricing_period: "per week"
        },
        overrides
      )
    end

    test "accepts valid meeting days" do
      attrs = valid_changeset_attrs(%{meeting_days: ["Monday", "Wednesday"]})
      changeset = ProgramSchema.changeset(%ProgramSchema{}, attrs)
      assert changeset.valid?
    end

    test "accepts empty meeting days" do
      attrs = valid_changeset_attrs(%{meeting_days: []})
      changeset = ProgramSchema.changeset(%ProgramSchema{}, attrs)
      assert changeset.valid?
    end

    test "rejects invalid meeting days" do
      attrs = valid_changeset_attrs(%{meeting_days: ["Monday", "Funday"]})
      changeset = ProgramSchema.changeset(%ProgramSchema{}, attrs)
      refute changeset.valid?
      assert "contains invalid days: Funday" in errors_on(changeset).meeting_days
    end

    test "accepts valid time pairing" do
      attrs =
        valid_changeset_attrs(%{meeting_start_time: ~T[16:00:00], meeting_end_time: ~T[17:30:00]})

      changeset = ProgramSchema.changeset(%ProgramSchema{}, attrs)
      assert changeset.valid?
    end

    test "accepts both times nil" do
      attrs = valid_changeset_attrs(%{meeting_start_time: nil, meeting_end_time: nil})
      changeset = ProgramSchema.changeset(%ProgramSchema{}, attrs)
      assert changeset.valid?
    end

    test "rejects start_time without end_time" do
      attrs = valid_changeset_attrs(%{meeting_start_time: ~T[16:00:00]})
      changeset = ProgramSchema.changeset(%ProgramSchema{}, attrs)
      refute changeset.valid?

      assert "both start and end times must be set together" in errors_on(changeset).meeting_start_time
    end

    test "rejects end_time without start_time" do
      attrs = valid_changeset_attrs(%{meeting_end_time: ~T[17:00:00]})
      changeset = ProgramSchema.changeset(%ProgramSchema{}, attrs)
      refute changeset.valid?

      assert "both start and end times must be set together" in errors_on(changeset).meeting_start_time
    end

    test "rejects end_time before start_time" do
      attrs =
        valid_changeset_attrs(%{meeting_start_time: ~T[17:00:00], meeting_end_time: ~T[16:00:00]})

      changeset = ProgramSchema.changeset(%ProgramSchema{}, attrs)
      refute changeset.valid?
      assert "must be after start time" in errors_on(changeset).meeting_end_time
    end

    test "rejects end_time equal to start_time" do
      attrs =
        valid_changeset_attrs(%{meeting_start_time: ~T[16:00:00], meeting_end_time: ~T[16:00:00]})

      changeset = ProgramSchema.changeset(%ProgramSchema{}, attrs)
      refute changeset.valid?
      assert "must be after start time" in errors_on(changeset).meeting_end_time
    end

    test "validates start_date before end_date" do
      attrs =
        valid_changeset_attrs(%{
          start_date: ~D[2026-01-01],
          end_date: ~D[2026-06-30]
        })

      changeset = ProgramSchema.changeset(%ProgramSchema{}, attrs)
      assert changeset.valid?
    end

    test "rejects start_date strictly after end_date" do
      attrs =
        valid_changeset_attrs(%{
          start_date: ~D[2026-07-01],
          end_date: ~D[2026-06-30]
        })

      changeset = ProgramSchema.changeset(%ProgramSchema{}, attrs)
      refute changeset.valid?
      assert "must be on or before end date" in errors_on(changeset).start_date
    end

    test "accepts equal start_date and end_date (single-day workshop)" do
      attrs =
        valid_changeset_attrs(%{
          start_date: ~D[2026-06-15],
          end_date: ~D[2026-06-15]
        })

      changeset = ProgramSchema.changeset(%ProgramSchema{}, attrs)
      assert changeset.valid?
    end

    test "allows start_date without end_date" do
      attrs = valid_changeset_attrs(%{start_date: ~D[2026-01-01]})
      changeset = ProgramSchema.changeset(%ProgramSchema{}, attrs)
      assert changeset.valid?
    end
  end

  describe "create_changeset/2 security" do
    test "ignores provider_id from string-keyed params (form injection)" do
      # Simulate form params (string keys) — provider_id should NOT be cast
      string_attrs = %{
        "title" => "Injected Program",
        "description" => "Trying to inject provider_id",
        "category" => "education",
        "price" => "50.00",
        "provider_id" => Ecto.UUID.generate()
      }

      changeset = ProgramSchema.create_changeset(%ProgramSchema{}, string_attrs)

      # provider_id should not have been picked up from string-keyed params
      refute Ecto.Changeset.get_change(changeset, :provider_id)
    end

    test "accepts provider_id from atom-keyed attrs (programmatic input)" do
      provider_id = Ecto.UUID.generate()

      attrs = %{
        title: "Legit Program",
        description: "Created by server code",
        category: "education",
        price: Decimal.new("50.00"),
        provider_id: provider_id
      }

      changeset = ProgramSchema.create_changeset(%ProgramSchema{}, attrs)

      assert Ecto.Changeset.get_change(changeset, :provider_id) == provider_id
    end

    test "ignores instructor_id from string-keyed params" do
      string_attrs = %{
        "title" => "Program",
        "description" => "Description",
        "category" => "education",
        "price" => "50.00",
        "instructor_id" => Ecto.UUID.generate()
      }

      changeset = ProgramSchema.create_changeset(%ProgramSchema{}, string_attrs)

      refute Ecto.Changeset.get_change(changeset, :instructor_id)
    end

    test "accepts instructor fields from atom-keyed attrs" do
      instructor_id = Ecto.UUID.generate()

      attrs = %{
        title: "Program",
        description: "Description",
        category: "education",
        price: Decimal.new("50.00"),
        provider_id: Ecto.UUID.generate(),
        instructor_id: instructor_id,
        instructor_name: "Jane Doe",
        instructor_headshot_url: "https://example.com/photo.jpg"
      }

      changeset = ProgramSchema.create_changeset(%ProgramSchema{}, attrs)

      assert Ecto.Changeset.get_change(changeset, :instructor_id) == instructor_id
      assert Ecto.Changeset.get_change(changeset, :instructor_name) == "Jane Doe"

      assert Ecto.Changeset.get_change(changeset, :instructor_headshot_url) ==
               "https://example.com/photo.jpg"
    end
  end

  describe "create_changeset/2 validation" do
    defp valid_create_attrs(overrides \\ %{}) do
      Map.merge(
        %{
          title: "Summer Soccer Camp",
          description: "Fun soccer activities for kids",
          category: "sports",
          price: Decimal.new("150.00"),
          provider_id: Ecto.UUID.generate()
        },
        overrides
      )
    end

    test "valid with all required fields" do
      changeset = ProgramSchema.create_changeset(%ProgramSchema{}, valid_create_attrs())
      assert changeset.valid?
    end

    test "requires title" do
      changeset =
        ProgramSchema.create_changeset(%ProgramSchema{}, Map.delete(valid_create_attrs(), :title))

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).title
    end

    test "requires description" do
      changeset =
        ProgramSchema.create_changeset(
          %ProgramSchema{},
          Map.delete(valid_create_attrs(), :description)
        )

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).description
    end

    test "requires category" do
      changeset =
        ProgramSchema.create_changeset(
          %ProgramSchema{},
          Map.delete(valid_create_attrs(), :category)
        )

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).category
    end

    test "requires price" do
      changeset =
        ProgramSchema.create_changeset(%ProgramSchema{}, Map.delete(valid_create_attrs(), :price))

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).price
    end

    test "requires provider_id" do
      changeset =
        ProgramSchema.create_changeset(
          %ProgramSchema{},
          Map.delete(valid_create_attrs(), :provider_id)
        )

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).provider_id
    end

    test "rejects title exceeding 100 characters" do
      attrs = valid_create_attrs(%{title: String.duplicate("a", 101)})
      changeset = ProgramSchema.create_changeset(%ProgramSchema{}, attrs)
      refute changeset.valid?
      assert "should be at most 100 character(s)" in errors_on(changeset).title
    end

    test "rejects description exceeding 500 characters" do
      attrs = valid_create_attrs(%{description: String.duplicate("a", 501)})
      changeset = ProgramSchema.create_changeset(%ProgramSchema{}, attrs)
      refute changeset.valid?
      assert "should be at most 500 character(s)" in errors_on(changeset).description
    end

    test "rejects invalid category" do
      attrs = valid_create_attrs(%{category: "invalid_category"})
      changeset = ProgramSchema.create_changeset(%ProgramSchema{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).category
    end

    test "rejects negative price" do
      attrs = valid_create_attrs(%{price: Decimal.new("-1.00")})
      changeset = ProgramSchema.create_changeset(%ProgramSchema{}, attrs)
      refute changeset.valid?
      assert "must be greater than or equal to 0" in errors_on(changeset).price
    end

    test "accepts price of zero" do
      attrs = valid_create_attrs(%{price: Decimal.new("0")})
      changeset = ProgramSchema.create_changeset(%ProgramSchema{}, attrs)
      assert changeset.valid?
    end

    test "accepts scheduling fields at creation" do
      attrs =
        valid_create_attrs(%{
          meeting_days: ["Monday", "Wednesday"],
          meeting_start_time: ~T[15:00:00],
          meeting_end_time: ~T[17:00:00],
          start_date: ~D[2026-03-01]
        })

      changeset = ProgramSchema.create_changeset(%ProgramSchema{}, attrs)
      assert changeset.valid?
    end

    test "rejects invalid meeting days at creation" do
      attrs = valid_create_attrs(%{meeting_days: ["Funday"]})
      changeset = ProgramSchema.create_changeset(%ProgramSchema{}, attrs)
      refute changeset.valid?
      assert "contains invalid days: Funday" in errors_on(changeset).meeting_days
    end

    test "accepts end_date at creation" do
      attrs =
        valid_create_attrs(%{
          start_date: ~D[2026-03-01],
          end_date: ~D[2026-06-30]
        })

      changeset = ProgramSchema.create_changeset(%ProgramSchema{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :end_date) == ~D[2026-06-30]
    end
  end

  describe "update_changeset/2" do
    defp valid_update_attrs(overrides \\ %{}) do
      Map.merge(
        %{
          title: "Updated Program",
          description: "Updated description",
          category: "sports",
          price: Decimal.new("200.00")
        },
        overrides
      )
    end

    defp existing_schema do
      %ProgramSchema{
        id: Ecto.UUID.generate(),
        title: "Original",
        description: "Original description",
        category: "sports",
        price: Decimal.new("100.00"),
        lock_version: 1
      }
    end

    test "valid with all required fields" do
      changeset = ProgramSchema.update_changeset(existing_schema(), valid_update_attrs())
      assert changeset.valid?
    end

    test "requires title" do
      attrs = valid_update_attrs(%{title: nil})
      changeset = ProgramSchema.update_changeset(existing_schema(), attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).title
    end

    test "requires description" do
      attrs = valid_update_attrs(%{description: nil})
      changeset = ProgramSchema.update_changeset(existing_schema(), attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).description
    end

    test "requires category" do
      attrs = valid_update_attrs(%{category: nil})
      changeset = ProgramSchema.update_changeset(existing_schema(), attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).category
    end

    test "requires price" do
      attrs = valid_update_attrs(%{price: nil})
      changeset = ProgramSchema.update_changeset(existing_schema(), attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).price
    end

    test "applies optimistic locking" do
      changeset = ProgramSchema.update_changeset(existing_schema(), valid_update_attrs())
      assert changeset.valid?
      # optimistic_lock registers a filter and incrementer; lock_version is in the changeset
      assert Map.has_key?(changeset.filters, :lock_version)
    end

    test "rejects title exceeding 100 characters" do
      attrs = valid_update_attrs(%{title: String.duplicate("a", 101)})
      changeset = ProgramSchema.update_changeset(existing_schema(), attrs)
      refute changeset.valid?
      assert "should be at most 100 character(s)" in errors_on(changeset).title
    end

    test "rejects description exceeding 500 characters" do
      attrs = valid_update_attrs(%{description: String.duplicate("a", 501)})
      changeset = ProgramSchema.update_changeset(existing_schema(), attrs)
      refute changeset.valid?
      assert "should be at most 500 character(s)" in errors_on(changeset).description
    end

    test "rejects invalid category" do
      attrs = valid_update_attrs(%{category: "invalid_category"})
      changeset = ProgramSchema.update_changeset(existing_schema(), attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).category
    end

    test "rejects negative price" do
      attrs = valid_update_attrs(%{price: Decimal.new("-5.00")})
      changeset = ProgramSchema.update_changeset(existing_schema(), attrs)
      refute changeset.valid?
      assert "must be greater than or equal to 0" in errors_on(changeset).price
    end

    test "accepts scheduling fields on update" do
      attrs =
        valid_update_attrs(%{
          meeting_days: ["Tuesday", "Thursday"],
          meeting_start_time: ~T[14:00:00],
          meeting_end_time: ~T[16:00:00],
          start_date: ~D[2026-03-01]
        })

      changeset = ProgramSchema.update_changeset(existing_schema(), attrs)
      assert changeset.valid?
    end

    test "rejects invalid meeting days on update" do
      attrs = valid_update_attrs(%{meeting_days: ["Notaday"]})
      changeset = ProgramSchema.update_changeset(existing_schema(), attrs)
      refute changeset.valid?
      assert "contains invalid days: Notaday" in errors_on(changeset).meeting_days
    end

    test "rejects unpaired times on update" do
      attrs = valid_update_attrs(%{meeting_start_time: ~T[14:00:00]})
      changeset = ProgramSchema.update_changeset(existing_schema(), attrs)
      refute changeset.valid?

      assert "both start and end times must be set together" in errors_on(changeset).meeting_start_time
    end
  end

  describe "registration period validation" do
    defp valid_registration_create_attrs(overrides) do
      Map.merge(
        %{
          title: "Summer Soccer Camp",
          description: "Fun soccer activities for kids",
          category: "sports",
          price: Decimal.new("150.00"),
          provider_id: Ecto.UUID.generate()
        },
        overrides
      )
    end

    defp existing_registration_schema do
      %ProgramSchema{
        id: Ecto.UUID.generate(),
        title: "Original",
        description: "Original description",
        category: "sports",
        price: Decimal.new("100.00"),
        lock_version: 1
      }
    end

    test "accepts valid registration dates in create_changeset" do
      attrs =
        valid_registration_create_attrs(%{
          registration_start_date: ~D[2026-02-01],
          registration_end_date: ~D[2026-03-01]
        })

      changeset = ProgramSchema.create_changeset(%ProgramSchema{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :registration_start_date) == ~D[2026-02-01]
      assert Ecto.Changeset.get_change(changeset, :registration_end_date) == ~D[2026-03-01]
    end

    test "accepts valid registration dates in update_changeset" do
      attrs = %{
        title: "Updated",
        description: "Updated description",
        category: "sports",
        price: Decimal.new("200.00"),
        registration_start_date: ~D[2026-02-01],
        registration_end_date: ~D[2026-03-01]
      }

      changeset = ProgramSchema.update_changeset(existing_registration_schema(), attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :registration_start_date) == ~D[2026-02-01]
      assert Ecto.Changeset.get_change(changeset, :registration_end_date) == ~D[2026-03-01]
    end

    test "rejects registration_start_date on or after registration_end_date" do
      attrs =
        valid_registration_create_attrs(%{
          registration_start_date: ~D[2026-03-15],
          registration_end_date: ~D[2026-03-01]
        })

      changeset = ProgramSchema.create_changeset(%ProgramSchema{}, attrs)
      refute changeset.valid?

      assert "must be before registration end date" in errors_on(changeset).registration_start_date
    end

    test "rejects registration_start_date equal to registration_end_date" do
      attrs =
        valid_registration_create_attrs(%{
          registration_start_date: ~D[2026-03-01],
          registration_end_date: ~D[2026-03-01]
        })

      changeset = ProgramSchema.create_changeset(%ProgramSchema{}, attrs)
      refute changeset.valid?

      assert "must be before registration end date" in errors_on(changeset).registration_start_date
    end

    test "allows registration_start_date without registration_end_date" do
      attrs = valid_registration_create_attrs(%{registration_start_date: ~D[2026-02-01]})
      changeset = ProgramSchema.create_changeset(%ProgramSchema{}, attrs)
      assert changeset.valid?
    end

    test "allows registration_end_date without registration_start_date" do
      attrs = valid_registration_create_attrs(%{registration_end_date: ~D[2026-03-01]})
      changeset = ProgramSchema.create_changeset(%ProgramSchema{}, attrs)
      assert changeset.valid?
    end
  end
end
