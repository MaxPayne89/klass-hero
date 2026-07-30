defmodule KlassHero.Enrollment.ImportEnrollmentCsvTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Enrollment.BulkEnrollmentInvite
  alias KlassHero.Enrollment.ImportEnrollmentCsv
  alias KlassHero.Repo
  # -- setup helpers ---------------------------------------------------------

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

      assert Repo.aggregate(BulkEnrollmentInvite, :count) == 2
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

      # EnqueueInviteEmails runs inline at the end of the import.
      invites = Repo.all(BulkEnrollmentInvite)
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

      invites = Repo.all(BulkEnrollmentInvite)
      alice_invite = Enum.find(invites, &(&1.child_first_name == "Alice"))
      bob_invite = Enum.find(invites, &(&1.child_first_name == "Bob"))

      assert alice_invite.program_id == program1.id
      assert alice_invite.provider_id == provider.id
      assert alice_invite.child_date_of_birth == ~D[2017-03-15]
      assert alice_invite.guardian_email == "alice@test.com"
      assert alice_invite.school_grade == 2
      assert alice_invite.school_name == "BIS"
      # EnqueueInviteEmails tokens the invite and the inline Oban worker sends the
      # email, so the status has already moved past :pending by the time we read.
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

      assert Repo.aggregate(BulkEnrollmentInvite, :count) == 2
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

      assert Repo.aggregate(BulkEnrollmentInvite, :count) == 2

      assert [%{row: 3, category: :validation, errors: errors}] = failed
      assert {:child_first_name, "is required"} in errors
    end

    test "every row fails validation -> created: 0, failed has all rows", %{provider: provider} do
      csv = build_csv([%{first: ""}, %{first: "", email: "x@y.com"}])

      assert {:ok, %{created: 0, failed: failed}} =
               ImportEnrollmentCsv.execute(provider.id, csv)

      assert length(failed) == 2
      assert Enum.all?(failed, &(&1.category == :validation))
      assert Repo.aggregate(BulkEnrollmentInvite, :count) == 0
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
      %BulkEnrollmentInvite{
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

    test "header-only CSV returns :empty_csv fatal", %{provider: provider} do
      headers_only = Enum.map_join(@csv_header_row, ",", &csv_escape/1)

      assert {:error, %{parse_errors: [{0, msg}]}} =
               ImportEnrollmentCsv.execute(provider.id, headers_only)

      assert msg =~ "empty"
    end

    test "header + only blank lines returns :empty_csv fatal", %{provider: provider} do
      csv = Enum.map_join(@csv_header_row, ",", &csv_escape/1) <> "\n\n\n"

      assert {:error, %{parse_errors: [{0, msg}]}} =
               ImportEnrollmentCsv.execute(provider.id, csv)

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

  # -- invite emails -----------------------------------------------------------

  # An import tokens and emails the pending invites of the programs it created rows
  # in — and only those. This used to be asserted on the shape of the
  # `bulk_invites_imported` event; the event has no reader now, so assert what a
  # guardian would notice instead: whether a token was issued and a job enqueued.
  describe "execute/2 - invite emails" do
    setup :setup_provider_with_programs

    test "tokens every imported invite when all rows succeed", %{
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

      assert [_, _] = tokened_invites()
      assert MapSet.new(tokened_invites(), & &1.program_id) == MapSet.new([program1.id, program2.id])
    end

    test "leaves a program alone when none of its rows succeeded", %{
      provider: provider,
      program1: program1,
      program2: program2
    } do
      # A pending invite already waiting in program2, from some earlier import.
      {:ok, _} =
        KlassHero.Enrollment.create_invite(%{
          program_id: program2.id,
          provider_id: provider.id,
          child_first_name: "Waiting",
          child_last_name: "Child",
          child_date_of_birth: ~D[2016-01-01],
          guardian_email: "waiting@x.com"
        })

      # program1's row succeeds; program2's fails validation (missing first name).
      csv =
        build_csv([
          %{first: "Alice", last: "A", email: "alice@x.com", program: program1.title},
          %{first: "", last: "B", email: "bob@x.com", program: program2.title}
        ])

      assert {:ok, %{created: 1, failed: [%{category: :validation}]}} =
               ImportEnrollmentCsv.execute(provider.id, csv)

      assert [%{program_id: tokened}] = tokened_invites()
      assert tokened == program1.id
    end

    test "tokens nothing when no row succeeded", %{provider: provider} do
      csv = build_csv([%{first: ""}, %{first: "", email: "x@y.com"}])

      assert {:ok, %{created: 0}} = ImportEnrollmentCsv.execute(provider.id, csv)

      assert [] = tokened_invites()
    end

    defp tokened_invites do
      Repo.all(from(i in BulkEnrollmentInvite, where: not is_nil(i.invite_token)))
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

      assert Repo.aggregate(BulkEnrollmentInvite, :count) == 2

      halt_entry =
        Enum.find(failed, fn f -> f.category == :parse and f.errors =~ "Stream halted" end)

      assert halt_entry, "expected a :parse halt entry"
      # The halt entry now carries the user-visible row number (2-based: header is
      # row 1) where parsing died, instead of nil. The bad row is the 4th file
      # line (header + 2 ok rows + bad) so it surfaces as row 4.
      assert is_integer(halt_entry.row)
      assert halt_entry.row == 4
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
