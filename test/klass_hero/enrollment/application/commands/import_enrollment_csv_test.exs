defmodule KlassHero.Enrollment.Application.Commands.ImportEnrollmentCsvTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Enrollment.Adapters.Driven.Persistence.Schemas.BulkEnrollmentInviteSchema
  alias KlassHero.Enrollment.Application.Commands.ImportEnrollmentCsv
  alias KlassHero.Repo
  # -- setup helpers ---------------------------------------------------------
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.DomainEventBus

  defp setup_provider_with_programs(_context) do
    provider = insert(:provider_profile_schema)
    program1 = insert(:program_schema, provider_id: provider.id, title: "Ballsports & Parkour")
    program2 = insert(:program_schema, provider_id: provider.id, title: "Organic Arts")
    %{provider: provider, program1: program1, program2: program2}
  end

  # -- CSV builder -----------------------------------------------------------

  @csv_defaults %{
    first: "Alice",
    last: "Smith",
    dob: "1/1/2016",
    parent_first: "Bob",
    parent_last: "Smith",
    email: "parent@example.com",
    parent2_first: "",
    parent2_last: "",
    parent2_email: "",
    grade: "",
    school: "",
    has_medical: "",
    medical: "",
    nut_allergy: "",
    photo_marketing: "",
    photo_social: "",
    program: "Ballsports & Parkour",
    instructor: "",
    season: "Test Season"
  }

  @csv_field_order ~w(first last dob parent_first parent_last email
    parent2_first parent2_last parent2_email grade school has_medical
    medical nut_allergy photo_marketing photo_social program instructor season)a

  @csv_header_row [
    "Participant information: First name",
    "Participant information: Last name",
    "Participant information: Date of birth",
    "Parent/guardian information: First name",
    "Parent/guardian information: Last name",
    "Parent/guardian information: Email address",
    "Parent/guardian 2 information: First name",
    "Parent/guardian 2 information: Last name",
    "Parent/guardian 2 information: Email address",
    "School information: Grade",
    "School information: Name",
    "Medical/allergy information: Do you have medical conditions and special needs?",
    "Medical/allergy information: Medical conditions and special needs",
    "Medical/allergy information: Nut allergy",
    ~s|Photography/video release permission: I agree that photos showing my child at camp may appear in marketing materials (e.g. posters, website) free of charge. this agreement is valid for unlimited time for all types of existing media and those that may be created.|,
    ~s|Photography/video release permission: I agree that photos and films showing my child participating in activities may appear for marketing purposes on prime youth's social media channels (e.g. facebook, instagram, youtube) free of charge, valid for unlimited time and without revealing my children's identity.|,
    "Program",
    "Instructor",
    "Season"
  ]

  defp build_csv(rows) do
    headers = Enum.map_join(@csv_header_row, ",", &csv_escape/1)

    data_rows =
      Enum.map(rows, fn row ->
        merged = Map.merge(@csv_defaults, row)
        Enum.map_join(@csv_field_order, ",", &csv_escape(merged[&1]))
      end)

    [headers | data_rows] |> Enum.join("\n")
  end

  defp csv_escape(value) when is_binary(value) do
    if String.contains?(value, [",", "\"", "\n"]) do
      "\"" <> String.replace(value, "\"", "\"\"") <> "\""
    else
      value
    end
  end

  defp build_data_row(overrides) do
    merged = Map.merge(@csv_defaults, overrides)
    Enum.map_join(@csv_field_order, ",", &csv_escape(merged[&1]))
  end

  # -- happy path (updated to new return shape) --------------------------------

  describe "execute/2 happy path" do
    setup :setup_provider_with_programs

    test "imports valid CSV with 2 rows across 2 programs", %{provider: provider} do
      csv =
        build_csv([
          %{
            first: "Alice",
            last: "Smith",
            email: "alice@test.com",
            program: "Ballsports & Parkour"
          },
          %{first: "Bob", last: "Jones", email: "bob@test.com", program: "Organic Arts"}
        ])

      assert {:ok, %{created: 2, failed: []}} = ImportEnrollmentCsv.execute(provider.id, csv)

      assert Repo.aggregate(BulkEnrollmentInviteSchema, :count) == 2
    end

    test "assigns invite tokens after successful import", %{provider: provider} do
      csv =
        build_csv([
          %{
            first: "Alice",
            last: "Smith",
            email: "alice@test.com",
            program: "Ballsports & Parkour"
          },
          %{first: "Bob", last: "Jones", email: "bob@test.com", program: "Organic Arts"}
        ])

      assert {:ok, %{created: 2, failed: []}} = ImportEnrollmentCsv.execute(provider.id, csv)

      # Trigger: EnqueueInviteEmails handler runs via DomainEventBus
      # Why: the bulk_invites_imported event should fire after persist,
      #      causing the handler to assign tokens synchronously
      # Outcome: every invite has a non-nil invite_token
      invites = Repo.all(BulkEnrollmentInviteSchema)
      assert Enum.all?(invites, fn inv -> inv.invite_token != nil end)
    end

    test "persists correct data for each row", %{
      provider: provider,
      program1: program1,
      program2: program2
    } do
      csv =
        build_csv([
          %{
            first: "Alice",
            last: "Smith",
            dob: "3/15/2017",
            email: "alice@test.com",
            parent_first: "Carol",
            parent_last: "Smith",
            program: "Ballsports & Parkour",
            grade: "2",
            school: "BIS"
          },
          %{
            first: "Bob",
            last: "Jones",
            dob: "12/1/2016",
            email: "bob@test.com",
            parent_first: "David",
            parent_last: "Jones",
            program: "Organic Arts",
            nut_allergy: "Yes",
            photo_marketing: "Yes"
          }
        ])

      assert {:ok, %{created: 2, failed: []}} = ImportEnrollmentCsv.execute(provider.id, csv)

      invites = Repo.all(BulkEnrollmentInviteSchema)
      alice_invite = Enum.find(invites, &(&1.child_first_name == "Alice"))
      bob_invite = Enum.find(invites, &(&1.child_first_name == "Bob"))

      assert alice_invite.program_id == program1.id
      assert alice_invite.provider_id == provider.id
      assert alice_invite.child_date_of_birth == ~D[2017-03-15]
      assert alice_invite.guardian_email == "alice@test.com"
      assert alice_invite.school_grade == 2
      assert alice_invite.school_name == "BIS"
      # Trigger: event handler + Oban inline worker run synchronously in test
      # Why: bulk_invites_imported event fires after persist, handler assigns
      #      tokens, and Oban inline worker sends email + transitions status
      # Outcome: status is "invite_sent" (not "pending") by the time we read
      assert alice_invite.status == :invite_sent

      assert bob_invite.program_id == program2.id
      assert bob_invite.nut_allergy == true
      assert bob_invite.consent_photo_marketing == true
    end
  end

  # -- case-insensitive program matching --------------------------------------

  describe "execute/2 case-insensitive program matching" do
    setup :setup_provider_with_programs

    test "imports CSV with differently-cased program names", %{provider: provider} do
      csv =
        build_csv([
          %{
            first: "Alice",
            last: "Smith",
            email: "alice@test.com",
            program: "ballsports & parkour"
          },
          %{first: "Bob", last: "Jones", email: "bob@test.com", program: "ORGANIC ARTS"},
          %{first: "Carol", last: "Lee", email: "carol@test.com", program: "Ballsports & Parkour"}
        ])

      assert {:ok, %{created: 3, failed: []}} = ImportEnrollmentCsv.execute(provider.id, csv)
    end
  end

  # -- case-insensitive collision detection ------------------------------------

  describe "execute/2 case-insensitive title collisions" do
    test "returns error when provider has programs differing only by case" do
      provider = insert(:provider_profile_schema)
      insert(:program_schema, provider_id: provider.id, title: "Yoga")
      insert(:program_schema, provider_id: provider.id, title: "YOGA")

      csv =
        build_csv([
          %{first: "Alice", last: "Smith", email: "alice@test.com", program: "Yoga"}
        ])

      assert {:error, %{parse_errors: [{0, msg}]}} =
               ImportEnrollmentCsv.execute(provider.id, csv)

      assert msg =~ "unique ignoring case"
      assert msg =~ "Yoga"
      assert msg =~ "YOGA"
    end
  end

  # -- no programs -----------------------------------------------------------

  describe "execute/2 no programs" do
    test "returns error when provider has no programs" do
      provider = insert(:provider_profile_schema)

      csv =
        build_csv([
          %{first: "Alice", last: "Smith", email: "parent@test.com", program: "Any Program"}
        ])

      assert {:error, %{parse_errors: [{0, msg}]}} =
               ImportEnrollmentCsv.execute(provider.id, csv)

      assert msg =~ "No programs found"
    end
  end

  # -- parse errors (whole-file fatals) ---------------------------------------

  describe "execute/2 parse errors" do
    setup :setup_provider_with_programs

    test "returns parse error for empty CSV", %{provider: provider} do
      assert {:error, %{parse_errors: [{0, msg}]}} = ImportEnrollmentCsv.execute(provider.id, "")
      assert msg =~ "empty"
    end

    test "returns parse error for invalid headers", %{provider: provider} do
      csv = "Wrong,Headers\nval1,val2\n"

      assert {:error, %{parse_errors: [{0, msg}]}} =
               ImportEnrollmentCsv.execute(provider.id, csv)

      assert msg =~ "Missing required columns"
    end
  end

  # -- per-row outcomes (new shape) ------------------------------------------

  describe "execute/2 - return shape and per-row outcomes" do
    setup :setup_provider_with_programs

    test "returns {:ok, %{created: n, failed: []}} when all rows valid", %{provider: provider} do
      csv = build_csv([%{first: "Alice"}, %{first: "Bob", email: "bob@x.com"}])

      assert {:ok, %{created: 2, failed: []}} =
               ImportEnrollmentCsv.execute(provider.id, csv)

      assert Repo.aggregate(BulkEnrollmentInviteSchema, :count) == 2
    end

    test "persists valid rows and reports invalid ones when mixed", %{provider: provider} do
      csv =
        build_csv([
          %{first: "Alice"},
          %{first: "", email: "alice@x.com"},
          %{first: "Bob", email: "bob@x.com"}
        ])

      assert {:ok, %{created: 2, failed: failed}} =
               ImportEnrollmentCsv.execute(provider.id, csv)

      assert Repo.aggregate(BulkEnrollmentInviteSchema, :count) == 2

      assert [%{row: 3, category: :validation, errors: errors}] = failed
      assert {:child_first_name, "is required"} in errors
    end

    test "every row fails validation -> created: 0, failed has all rows", %{provider: provider} do
      csv = build_csv([%{first: ""}, %{first: "", email: "x@y.com"}])

      assert {:ok, %{created: 0, failed: failed}} =
               ImportEnrollmentCsv.execute(provider.id, csv)

      assert length(failed) == 2
      assert Enum.all?(failed, &(&1.category == :validation))
      assert Repo.aggregate(BulkEnrollmentInviteSchema, :count) == 0
    end

    test "in-batch duplicate is reported per-row, first row still imported", %{provider: provider} do
      csv =
        build_csv([
          %{first: "Alice", last: "X", email: "a@x.com"},
          %{first: "Alice", last: "X", email: "a@x.com"}
        ])

      assert {:ok, %{created: 1, failed: [%{row: 3, category: :duplicate, errors: msg}]}} =
               ImportEnrollmentCsv.execute(provider.id, csv)

      assert msg =~ "Duplicate entry in CSV"
    end

    test "existing DB duplicate is reported per-row, other rows still imported", %{
      provider: provider,
      program1: program
    } do
      # Trigger: seed a pre-existing invite so the use case sees a DB duplicate
      # Why: Repo.insert! on the schema struct stays valid regardless of the
      #      use case's persistence API
      # Outcome: direct struct insert bypasses changeset validation — we
      #          control the data, so the FK-satisfying fields are enough
      %BulkEnrollmentInviteSchema{
        program_id: program.id,
        provider_id: provider.id,
        child_first_name: "Alice",
        child_last_name: "X",
        child_date_of_birth: ~D[2016-01-01],
        guardian_email: "a@x.com",
        status: :pending
      }
      |> Repo.insert!()

      csv =
        build_csv([
          %{first: "Bob", last: "Y", email: "b@x.com"},
          %{first: "Alice", last: "X", email: "a@x.com"}
        ])

      assert {:ok, %{created: 1, failed: [%{row: 3, category: :duplicate, errors: msg}]}} =
               ImportEnrollmentCsv.execute(provider.id, csv)

      assert msg =~ "already exists"
    end

    test "row-level parse errors (bad date) become :parse failures, others import", %{
      provider: provider
    } do
      csv =
        build_csv([
          %{first: "Alice", dob: "1/1/2016"},
          %{first: "Bob", dob: "not-a-date", email: "bob@x.com"},
          %{first: "Carol", dob: "3/3/2018", email: "carol@x.com"}
        ])

      assert {:ok, %{created: 2, failed: [%{row: 3, category: :parse, errors: msg}]}} =
               ImportEnrollmentCsv.execute(provider.id, csv)

      assert msg =~ "invalid date"
    end

    test "no programs for provider -> {:error, %{parse_errors: ...}} whole-file fatal" do
      provider = insert(:provider_profile_schema)

      csv = build_csv([%{first: "Alice"}])

      assert {:error, %{parse_errors: [{0, msg}]}} =
               ImportEnrollmentCsv.execute(provider.id, csv)

      assert msg =~ "No programs"
    end

    test "empty CSV -> {:error, %{parse_errors: ...}}", %{provider: provider} do
      assert {:error, %{parse_errors: [{0, msg}]}} =
               ImportEnrollmentCsv.execute(provider.id, "")

      assert msg =~ "empty"
    end

    test "missing headers -> {:error, %{parse_errors: ...}}", %{provider: provider} do
      csv = "Wrong,Headers\nAlice,Smith"

      assert {:error, %{parse_errors: [{0, msg}]}} =
               ImportEnrollmentCsv.execute(provider.id, csv)

      assert msg =~ "Missing required columns"
    end
  end

  # -- cross-chunk dedup ---------------------------------------------------------

  describe "execute/2 - cross-chunk dedup" do
    setup :setup_provider_with_programs

    test "in-batch dedup detects duplicates split across chunk boundary", %{provider: provider} do
      # rows = [A, B, A] with chunk_size: 2 -> chunk 1 = [A, B], chunk 2 = [A]
      csv =
        build_csv([
          %{first: "Alice", last: "X", email: "a@x.com"},
          %{first: "Bob", last: "Y", email: "b@x.com"},
          %{first: "Alice", last: "X", email: "a@x.com"}
        ])

      assert {:ok, %{created: 2, failed: [%{row: 4, category: :duplicate, errors: msg}]}} =
               ImportEnrollmentCsv.execute(provider.id, csv, chunk_size: 2)

      assert msg =~ "Duplicate entry in CSV"
    end
  end

  # -- event firing ------------------------------------------------------------

  describe "execute/2 - event firing" do
    setup :setup_provider_with_programs

    # Subscribe an anonymous handler on the Enrollment DomainEventBus that
    # forwards every :bulk_invites_imported event to the test process.
    # EventDispatchHelper.dispatch runs handlers synchronously in the caller's
    # process, so this delivers reliably without async/PubSub timing concerns.
    setup do
      test_pid = self()

      DomainEventBus.subscribe(
        KlassHero.Enrollment,
        :bulk_invites_imported,
        fn event ->
          send(test_pid, {:bulk_invites_imported, event})
          :ok
        end
      )

      :ok
    end

    test "fires bulk_invites_imported with success-only program_ids when created > 0", %{
      provider: provider,
      program1: program1,
      program2: program2
    } do
      csv =
        build_csv([
          %{first: "Alice", last: "A", email: "alice@x.com", program: program1.title},
          %{first: "Bob", last: "B", email: "bob@x.com", program: program2.title}
        ])

      assert {:ok, %{created: 2, failed: []}} = ImportEnrollmentCsv.execute(provider.id, csv)

      provider_id = provider.id

      assert_receive {:bulk_invites_imported,
                      %DomainEvent{
                        event_type: :bulk_invites_imported,
                        payload: %{provider_id: ^provider_id, program_ids: ids, count: 2}
                      }},
                     1_000

      assert program1.id in ids
      assert program2.id in ids
      assert length(ids) == 2
    end

    test "fires event with only programs that had at least one success", %{
      provider: provider,
      program1: program1,
      program2: program2
    } do
      # program1 row succeeds; program2 row fails validation (missing first name).
      csv =
        build_csv([
          %{first: "Alice", last: "A", email: "alice@x.com", program: program1.title},
          %{first: "", last: "B", email: "bob@x.com", program: program2.title}
        ])

      assert {:ok, %{created: 1, failed: [%{category: :validation}]}} =
               ImportEnrollmentCsv.execute(provider.id, csv)

      assert_receive {:bulk_invites_imported,
                      %DomainEvent{
                        event_type: :bulk_invites_imported,
                        payload: %{program_ids: ids, count: 1}
                      }},
                     1_000

      assert ids == [program1.id]
    end

    test "does NOT fire event when created == 0", %{provider: provider} do
      csv = build_csv([%{first: ""}, %{first: "", email: "x@y.com"}])

      assert {:ok, %{created: 0}} = ImportEnrollmentCsv.execute(provider.id, csv)

      refute_receive {:bulk_invites_imported, _}, 500
    end
  end

  # -- mid-stream halt -----------------------------------------------------------

  describe "execute/2 - mid-stream halt" do
    setup :setup_provider_with_programs

    test "earlier rows persist, halt entry appended on ParseError", %{provider: provider} do
      # Construct a CSV where the third data row has unbalanced quotes -> NimbleCSV.ParseError.
      # chunk_size: 2 puts rows 1 and 2 in the first chunk (committed before the bad chunk),
      # and the bad row alone in the second chunk which causes the ParseError halt.
      headers = Enum.map_join(@csv_header_row, ",", &csv_escape/1)
      row1 = build_data_row(%{first: "Alice"})
      row2 = build_data_row(%{first: "Bob", email: "bob@x.com"})
      bad_row = ~s|Eve,"Unclosed,1/1/2018,Frank,Jones,frank@x.com,,,,,,,,,,,Ballsports & Parkour,,Spring|
      csv = Enum.join([headers, row1, row2, bad_row], "\n")

      assert {:ok, %{created: 2, failed: failed}} =
               ImportEnrollmentCsv.execute(provider.id, csv, chunk_size: 2)

      assert Repo.aggregate(BulkEnrollmentInviteSchema, :count) == 2

      halt_entry =
        Enum.find(failed, fn f -> f.category == :parse and is_nil(f.row) end)

      assert halt_entry, "expected a :parse halt entry"
      assert halt_entry.errors =~ "Stream halted"
    end
  end

  # -- failure category matrix ---------------------------------------------------

  describe "execute/2 - failure category matrix" do
    setup :setup_provider_with_programs

    @failure_cases [
      {%{first: ""}, :validation, :child_first_name, "is required"},
      {%{email: "not-an-email"}, :validation, :guardian_email, "must be a valid email"},
      {%{program: "Nonexistent Program"}, :validation, :program_name, "program not found"},
      {%{grade: "99"}, :validation, :school_grade, "must be between 1 and 13"}
    ]

    test "each case produces the expected failure category and field error", %{provider: provider} do
      for {row_overrides, expected_category, expected_field, expected_msg} <- @failure_cases do
        csv = build_csv([row_overrides])

        assert {:ok, %{created: 0, failed: [failure]}} =
                 ImportEnrollmentCsv.execute(provider.id, csv),
               "unexpected return shape for case #{inspect(row_overrides)}"

        assert failure.category == expected_category,
               "for #{inspect(row_overrides)}: expected category #{expected_category}, got #{failure.category}"

        found_pair = Enum.find(failure.errors, fn {f, _} -> f == expected_field end)

        assert found_pair,
               "for #{inspect(row_overrides)}: expected field #{expected_field} in #{inspect(failure.errors)}"

        {^expected_field, msg} = found_pair

        assert msg =~ expected_msg,
               "for #{inspect(row_overrides)}: expected msg ~= #{expected_msg}, got #{msg}"
      end
    end
  end

  # -- large CSV smoke test ------------------------------------------------------

  describe "execute/2 - large CSV smoke test" do
    setup :setup_provider_with_programs

    @tag :slow
    test "5_000 valid + 500 invalid rows complete with correct counts", %{provider: provider} do
      valid_rows = for n <- 1..5_000, do: %{first: "Valid#{n}", email: "valid#{n}@x.com"}
      invalid_rows = for n <- 1..500, do: %{first: "", email: "bad#{n}@x.com"}
      csv = build_csv(valid_rows ++ invalid_rows)

      {:ok, %{created: created, failed: failed}} =
        ImportEnrollmentCsv.execute(provider.id, csv)

      assert created == 5_000
      assert length(failed) == 500
      assert Enum.all?(failed, &(&1.category == :validation))
    end
  end
end
