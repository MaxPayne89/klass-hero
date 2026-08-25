defmodule KlassHero.Enrollment.Domain.Services.CsvParserTest do
  use ExUnit.Case, async: true

  # -- helpers ---------------------------------------------------------------
  alias KlassHero.Enrollment.Domain.Services.CsvParser

  defp headers do
    [
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
  end

  defp header_line do
    headers()
    |> Enum.map_join(",", &csv_escape/1)
  end

  defp build_csv(rows) do
    data_lines =
      Enum.map(rows, fn cells ->
        cells |> Enum.map_join(",", &csv_escape/1)
      end)

    [header_line() | data_lines]
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  # Trigger: CSV fields containing commas or quotes must be escaped
  # Why: NimbleCSV will misparse unquoted fields with commas
  # Outcome: fields are wrapped in double quotes when necessary
  defp csv_escape(value) when is_binary(value) do
    if String.contains?(value, [",", "\""]) do
      ~s|"#{String.replace(value, "\"", "\"\"")}"|
    else
      value
    end
  end

  # -- happy path ------------------------------------------------------------

  describe "parse/1 happy path" do
    test "parses valid rows into structured maps" do
      csv =
        build_csv([
          [
            "Avyan",
            "Srivastava",
            "1/1/2016",
            "Vaibhav",
            "Srivastava",
            "vaibhavinuk@gmail.com",
            "",
            "",
            "",
            "3",
            "",
            "",
            "",
            "",
            "",
            "",
            "Ballsports & Parkour",
            "",
            "Berlin International School 24/25: Semester 2"
          ]
        ])

      assert {:ok, [row]} = CsvParser.parse(csv)

      assert row == %{
               child_first_name: "Avyan",
               child_last_name: "Srivastava",
               child_date_of_birth: ~D[2016-01-01],
               guardian_first_name: "Vaibhav",
               guardian_last_name: "Srivastava",
               guardian_email: "vaibhavinuk@gmail.com",
               guardian2_first_name: nil,
               guardian2_last_name: nil,
               guardian2_email: nil,
               school_grade: 3,
               school_name: nil,
               medical_conditions: nil,
               nut_allergy: false,
               consent_photo_marketing: false,
               consent_photo_social_media: false,
               program_name: "Ballsports & Parkour",
               instructor_name: nil,
               season: "Berlin International School 24/25: Semester 2"
             }
    end

    test "parses multiple rows" do
      csv =
        build_csv([
          [
            "Avyan",
            "Srivastava",
            "1/1/2016",
            "Vaibhav",
            "Srivastava",
            "vaibhavinuk@gmail.com",
            "",
            "",
            "",
            "3",
            "",
            "",
            "",
            "",
            "",
            "",
            "Ballsports & Parkour",
            "",
            "Season 1"
          ],
          [
            "Eliana",
            "Ghandaih",
            "12/17/2015",
            "Afnan",
            "Alghamdi",
            "afnan.alghamdi@hotmail.com",
            "Essam",
            "Ghandaih",
            "dr_essam83@hotmail.com",
            "3",
            "",
            "No",
            "",
            "No",
            "Yes",
            "Yes",
            "Organic Arts",
            "Jala Salti",
            "Season 1"
          ]
        ])

      assert {:ok, rows} = CsvParser.parse(csv)
      assert length(rows) == 2

      second = Enum.at(rows, 1)
      assert second.child_first_name == "Eliana"
      assert second.guardian2_first_name == "Essam"
      assert second.guardian2_email == "dr_essam83@hotmail.com"
      assert second.consent_photo_marketing == true
      assert second.consent_photo_social_media == true
      assert second.instructor_name == "Jala Salti"
    end
  end

  # -- type conversions ------------------------------------------------------
  #
  # These four clusters share one shape (single-field override -> parsed
  # value) so they're tabular. Everything else in this file stays hand-written
  # — streaming/laziness, :parse_halt, BOM, and multi-line-quoted-field
  # scenarios are too heterogeneous to gain clarity from a table.

  @date_parsing_cases [
    {"1/1/2016", ~D[2016-01-01], "M/D/YYYY"},
    {"09/23/2017", ~D[2017-09-23], "MM/DD/YYYY"},
    {"1/31/2017", ~D[2017-01-31], "M/DD/YYYY"},
    {"03/09/2018", ~D[2018-03-09], "MM/D/YYYY"},
    {"12/17/2015", ~D[2015-12-17], "MM/DD/YYYY"}
  ]

  describe "date parsing" do
    test "parses M/D/YYYY and MM/DD/YYYY dates" do
      for {input, expected, label} <- @date_parsing_cases do
        csv = build_csv([row_with_overrides(child_date_of_birth: input)])

        assert {:ok, [row]} = CsvParser.parse(csv), label
        assert row.child_date_of_birth == expected, label
      end
    end
  end

  @boolean_mapping_cases [
    {"Yes", true},
    {"yes", true},
    {"YES", true},
    {"True", true},
    {"true", true},
    {"1", true},
    {"No", false},
    {"no", false},
    {"NO", false},
    {"", false}
  ]

  describe "boolean mapping" do
    test "maps CSV boolean strings to true/false, case-insensitively" do
      for {input, expected} <- @boolean_mapping_cases do
        csv = build_csv([row_with_overrides(nut_allergy: input, consent_photo_marketing: input)])

        assert {:ok, [row]} = CsvParser.parse(csv), "expected #{inspect(input)} to parse successfully"
        assert row.nut_allergy == expected, "expected #{inspect(input)} to map to #{expected}"
        assert row.consent_photo_marketing == expected, "expected #{inspect(input)} to map to #{expected}"
      end
    end
  end

  @grade_parsing_cases [
    {"3", 3, "numeric string maps to integer"},
    {"", nil, "empty string maps to nil"}
  ]

  describe "grade parsing" do
    test "maps CSV grade strings to integer or nil" do
      for {input, expected, label} <- @grade_parsing_cases do
        csv = build_csv([row_with_overrides(school_grade: input)])

        assert {:ok, [row]} = CsvParser.parse(csv), label
        assert row.school_grade == expected, label
      end
    end
  end

  @string_handling_cases [
    {:child_first_name, "Maxim ", "Maxim", "trims trailing whitespace"},
    {:school_name, "", nil, "empty string becomes nil"},
    {:instructor_name, "", nil, "empty string becomes nil"}
  ]

  describe "string handling" do
    test "trims whitespace and converts empty strings to nil" do
      for {field, input, expected, label} <- @string_handling_cases do
        csv = build_csv([row_with_overrides([{field, input}])])

        assert {:ok, [row]} = CsvParser.parse(csv), label
        assert Map.get(row, field) == expected, label
      end
    end
  end

  # -- error handling --------------------------------------------------------

  describe "error handling" do
    test "returns error for empty CSV" do
      assert {:error, :empty_csv} = CsvParser.parse("")
    end

    test "returns error for CSV with only headers" do
      csv = header_line() <> "\n"

      assert {:error, :empty_csv} = CsvParser.parse(csv)
    end

    test "returns error for invalid date with row number" do
      csv =
        build_csv([
          row_with_overrides(child_date_of_birth: "not-a-date")
        ])

      assert {:error, errors} = CsvParser.parse(csv)
      # parse/1 wraps parse_stream/1 in Stream.with_index(2), so row numbers are
      # 2-based (header = row 1, first data row = row 2). parse_stream/1 itself
      # is row-number-agnostic; callers thread positional context via with_index.
      assert [{2, reason}] = errors
      assert reason =~ "invalid date"
      assert reason =~ "child_date_of_birth"
      assert reason =~ "not-a-date"
    end

    test "returns error for invalid headers" do
      csv = "Wrong,Headers,Here\nval1,val2,val3\n"

      assert {:error, {:invalid_headers, missing}} = CsvParser.parse(csv)
      assert :child_first_name in missing
    end

    test "returns error for malformed CSV with mismatched quotes" do
      # validate_headers/1 catches structural breaks in the header line and returns
      # {:error, :malformed_csv}; parse/1 short-circuits via with and propagates it
      csv = "\"unclosed quote,value\n"
      assert {:error, :malformed_csv} = CsvParser.parse(csv)
    end
  end

  # -- quoted fields ---------------------------------------------------------

  describe "quoted fields" do
    test "parses quoted fields containing commas" do
      csv =
        build_csv([
          row_with_overrides(school_name: ~s|"2HB - BIS Kant international school, Thursday organic arts class "|)
        ])

      assert {:ok, [row]} = CsvParser.parse(csv)
      assert row.school_name =~ "2HB - BIS"
    end

    # RFC4180: a cell containing an embedded newline is legal as long as the
    # cell is wrapped in double quotes. The parser must keep that cell as a
    # single value, not shred the row into fragments on the literal newline.
    test "parses multi-line quoted field as a single row per RFC4180" do
      headers =
        "Participant information: First,Participant information: Last,Participant information: Date,Parent/guardian information: First,Parent/guardian information: Last,Parent/guardian information: Email,Parent/guardian 2 information: First,Parent/guardian 2 information: Last,Parent/guardian 2 information: Email,School information: Grade,School information: Name,Medical/allergy information: Do you have,Medical/allergy information: Medical,Medical/allergy information: Nut,Photography/video release permission: I agree that photos showing,Photography/video release permission: I agree that photos and films,Program,Instructor,Season"

      data =
        ~s|Alice,Smith,1/1/2016,Bob,Smith,bob@x.com,,,,,"Roosevelt\nHigh School",,,,,,Ballsports,,Spring|

      csv = headers <> "\n" <> data

      assert {:ok, [row]} = CsvParser.parse(csv)
      assert row.child_first_name == "Alice"
      assert row.school_name == "Roosevelt\nHigh School"
      assert row.program_name == "Ballsports"
    end
  end

  # -- BOM handling -----------------------------------------------------------

  describe "BOM handling" do
    test "parses CSV with UTF-8 BOM prefix correctly" do
      csv = <<0xEF, 0xBB, 0xBF>> <> build_csv([row_with_overrides(child_first_name: "Avyan")])

      assert {:ok, [row]} = CsvParser.parse(csv)
      assert row.child_first_name == "Avyan"
    end

    test "BOM-only input returns empty_csv error" do
      assert {:error, :empty_csv} = CsvParser.parse(<<0xEF, 0xBB, 0xBF>>)
    end

    test "BOM with only headers returns empty_csv error" do
      csv = <<0xEF, 0xBB, 0xBF>> <> header_line() <> "\n"

      assert {:error, :empty_csv} = CsvParser.parse(csv)
    end
  end

  # -- validate_headers/1 -------------------------------------------------------

  describe "validate_headers/1" do
    test "returns prepared payload with column_keys and remainder for a valid CSV" do
      csv =
        "Participant information: First,Participant information: Last,Participant information: Date,Parent/guardian information: First,Parent/guardian information: Last,Parent/guardian information: Email,Parent/guardian 2 information: First,Parent/guardian 2 information: Last,Parent/guardian 2 information: Email,School information: Grade,School information: Name,Medical/allergy information: Do you have,Medical/allergy information: Medical,Medical/allergy information: Nut,Photography/video release permission: I agree that photos showing,Photography/video release permission: I agree that photos and films,Program,Instructor,Season\nAlice,Smith,1/1/2016,Bob,Smith,p@x.com,,,,,,,,,,,Ballsports & Parkour,,Test"

      assert {:ok, %{column_keys: keys, remainder: rest}} =
               CsvParser.validate_headers(csv)

      assert :child_first_name in keys
      assert :program_name in keys
      assert String.starts_with?(rest, "Alice,Smith")
    end

    test "returns :empty_csv error for empty input" do
      assert {:error, :empty_csv} =
               CsvParser.validate_headers("")

      assert {:error, :empty_csv} =
               CsvParser.validate_headers("   \n  ")
    end

    test "returns invalid_headers error when required columns missing" do
      csv = "Wrong,Headers\nAlice,Smith"

      assert {:error, {:invalid_headers, missing}} =
               CsvParser.validate_headers(csv)

      assert :child_first_name in missing
      assert :program_name in missing
    end

    test "returns :malformed_csv when the header line is structurally broken" do
      # Unbalanced quote in header line
      csv = ~s(Participant information: First,"Unclosed,Program\nAlice,Smith,Ballsports)

      assert {:error, :malformed_csv} =
               CsvParser.validate_headers(csv)
    end

    test "strips UTF-8 BOM before parsing headers" do
      bom_csv =
        <<0xEF, 0xBB, 0xBF>> <>
          "Participant information: First,Participant information: Last,Participant information: Date,Parent/guardian information: First,Parent/guardian information: Last,Parent/guardian information: Email,Parent/guardian 2 information: First,Parent/guardian 2 information: Last,Parent/guardian 2 information: Email,School information: Grade,School information: Name,Medical/allergy information: Do you have,Medical/allergy information: Medical,Medical/allergy information: Nut,Photography/video release permission: I agree that photos showing,Photography/video release permission: I agree that photos and films,Program,Instructor,Season\nAlice,Smith,1/1/2016,Bob,Smith,p@x.com,,,,,,,,,,,Ballsports & Parkour,,Test"

      assert {:ok, %{column_keys: keys}} =
               CsvParser.validate_headers(bom_csv)

      assert :child_first_name in keys
    end
  end

  # -- parse_stream/1 -----------------------------------------------------------

  describe "parse_stream/1" do
    defp build_csv_with_rows(data_lines) do
      headers =
        "Participant information: First,Participant information: Last,Participant information: Date,Parent/guardian information: First,Parent/guardian information: Last,Parent/guardian information: Email,Parent/guardian 2 information: First,Parent/guardian 2 information: Last,Parent/guardian 2 information: Email,School information: Grade,School information: Name,Medical/allergy information: Do you have,Medical/allergy information: Medical,Medical/allergy information: Nut,Photography/video release permission: I agree that photos showing,Photography/video release permission: I agree that photos and films,Program,Instructor,Season"

      Enum.join([headers | data_lines], "\n")
    end

    test "yields {:ok, row_map} for each valid data row" do
      csv =
        build_csv_with_rows([
          "Alice,Smith,1/1/2016,Bob,Smith,bob@x.com,,,,,,,,,,,Ballsports,,Spring",
          "Carol,Doe,5/5/2017,Dan,Doe,dan@x.com,,,,,,,,,,,Arts,,Spring"
        ])

      {:ok, prepared} = CsvParser.validate_headers(csv)
      results = prepared |> CsvParser.parse_stream() |> Enum.to_list()

      assert [{:ok, row1}, {:ok, row2}] = results
      assert row1.child_first_name == "Alice"
      assert row1.program_name == "Ballsports"
      assert row2.child_first_name == "Carol"
    end

    test "yields {:error, message} for rows with bad data" do
      csv =
        build_csv_with_rows([
          "Alice,Smith,1/1/2016,Bob,Smith,bob@x.com,,,,,,,,,,,Ballsports,,Spring",
          "Carol,Doe,not-a-date,Dan,Doe,dan@x.com,,,,,,,,,,,Arts,,Spring",
          "Eve,Jones,3/3/2018,Frank,Jones,frank@x.com,,,,,,,,,,,Sports,,Spring"
        ])

      {:ok, prepared} = CsvParser.validate_headers(csv)
      results = prepared |> CsvParser.parse_stream() |> Enum.to_list()

      # parse_stream/1 emits 2-tuple shapes (no embedded row number). Callers
      # thread positional context via Stream.with_index/2 — see parse/1 for the
      # canonical 2-based scheme.
      assert [
               {:ok, %{child_first_name: "Alice"}},
               {:error, msg},
               {:ok, %{child_first_name: "Eve"}}
             ] = results

      assert msg =~ "invalid date"
    end

    test "returns empty stream when remainder is empty" do
      {:ok, prepared} = CsvParser.validate_headers(build_csv_with_rows([]))
      assert prepared |> CsvParser.parse_stream() |> Enum.to_list() == []
    end

    test "is lazy — does not parse beyond what is taken" do
      csv =
        build_csv_with_rows(
          for n <- 1..1000 do
            "Name#{n},Last,1/1/2016,Bob,Smith,bob@x.com,,,,,,,,,,,Ballsports,,Spring"
          end
        )

      {:ok, prepared} = CsvParser.validate_headers(csv)

      first_two = prepared |> CsvParser.parse_stream() |> Enum.take(2)
      assert length(first_two) == 2
      assert [{:ok, %{child_first_name: "Name1"}}, {:ok, %{child_first_name: "Name2"}}] = first_two
    end

    # Fix #4: blank lines must still emit an element so caller-side
    # Stream.with_index/2 stays aligned with the user's spreadsheet line
    # numbers. Previously a Stream.reject filtered blanks out BEFORE the
    # caller could index them, shifting subsequent row numbers down by one
    # for each blank.
    test "blank lines are emitted as row-level errors so caller indexing stays aligned" do
      csv =
        build_csv_with_rows([
          "Alice,Smith,1/1/2016,Bob,Smith,bob@x.com,,,,,,,,,,,Ballsports,,Spring",
          "",
          "Carol,Doe,5/5/2017,Dan,Doe,dan@x.com,,,,,,,,,,,Arts,,Spring"
        ])

      {:ok, prepared} = CsvParser.validate_headers(csv)
      results = prepared |> CsvParser.parse_stream() |> Enum.to_list()

      # parse_stream/1 emits 2-tuples only — row numbers are caller-owned.
      # The blank row appears between Alice and Carol so a caller using
      # Stream.with_index/2 sees Carol at its expected position.
      assert [
               {:ok, %{child_first_name: "Alice"}},
               {:error, _blank_msg},
               {:ok, %{child_first_name: "Carol"}}
             ] = results
    end

    # Fix #1: NimbleCSV's parse_stream handles RFC4180 multi-line quoted
    # fields. Verify a quoted cell with an embedded newline does not crash
    # the stream or produce a :parse_halt.
    test "parse_stream/1 preserves multi-line quoted cells as one row" do
      data =
        ~s|Alice,Smith,1/1/2016,Bob,Smith,bob@x.com,,,,,"Roosevelt\nHigh School",,,,,,Ballsports,,Spring|

      csv = build_csv_with_rows([data])

      {:ok, prepared} = CsvParser.validate_headers(csv)
      results = prepared |> CsvParser.parse_stream() |> Enum.to_list()

      assert [{:ok, row}] = results
      assert row.school_name == "Roosevelt\nHigh School"
    end

    # Fix #1/#9: structurally malformed CSV (mid-stream unbalanced quote)
    # must surface as a single :parse_halt sentinel — not raise, not yield
    # N halts. Row numbers are caller-owned via Stream.with_index/2.
    test "parse_stream/1 surfaces structural errors as a single :parse_halt" do
      csv =
        build_csv_with_rows([
          "Alice,Smith,1/1/2016,Bob,Smith,bob@x.com,,,,,,,,,,,Ballsports,,Spring",
          ~s|Bob,"Unclosed,2/2/2017,Carol,Smith,carol@x.com,,,,,,,,,,,Arts,,Spring|
        ])

      {:ok, prepared} = CsvParser.validate_headers(csv)
      results = prepared |> CsvParser.parse_stream() |> Enum.to_list()

      # Alice ok, then one :parse_halt with the malformed-cell message, then end.
      assert [
               {:ok, %{child_first_name: "Alice"}},
               {:parse_halt, msg}
             ] = results

      assert msg =~ "expected escape character"
    end
  end

  # -- partition_results halt semantics (Fix #9) -----------------------------

  describe "parse/1 with structural errors" do
    test "halts on first :parse_halt and emits a single error tuple" do
      headers =
        "Participant information: First,Participant information: Last,Participant information: Date,Parent/guardian information: First,Parent/guardian information: Last,Parent/guardian information: Email,Parent/guardian 2 information: First,Parent/guardian 2 information: Last,Parent/guardian 2 information: Email,School information: Grade,School information: Name,Medical/allergy information: Do you have,Medical/allergy information: Medical,Medical/allergy information: Nut,Photography/video release permission: I agree that photos showing,Photography/video release permission: I agree that photos and films,Program,Instructor,Season"

      # Two malformed lines back-to-back: only the first should surface as
      # an error; iteration must halt rather than emit one error per line.
      csv =
        headers <>
          "\n" <>
          ~s|Alice,"Unclosed,1/1/2016,Bob,Smith,b@x.com,,,,,,,,,,,Ballsports,,Spring| <>
          "\n" <>
          ~s|Carol,"AlsoUnclosed,2/2/2017,Dan,Smith,d@x.com,,,,,,,,,,,Arts,,Spring|

      assert {:error, errors} = CsvParser.parse(csv)
      assert length(errors) == 1
      assert [{row_num, msg}] = errors
      assert is_integer(row_num) and row_num > 0
      assert msg =~ "CSV file is malformed"
    end
  end

  # -- test row builder ------------------------------------------------------

  defp row_with_overrides(overrides) do
    defaults = %{
      child_first_name: "Test",
      child_last_name: "Child",
      child_date_of_birth: "1/1/2016",
      guardian_first_name: "Test",
      guardian_last_name: "Parent",
      guardian_email: "test@example.com",
      guardian2_first_name: "",
      guardian2_last_name: "",
      guardian2_email: "",
      school_grade: "",
      school_name: "",
      has_medical: "",
      medical_conditions: "",
      nut_allergy: "",
      consent_photo_marketing: "",
      consent_photo_social_media: "",
      program_name: "Test Program",
      instructor_name: "",
      season: "Test Season"
    }

    merged = Map.merge(defaults, Map.new(overrides))

    [
      merged.child_first_name,
      merged.child_last_name,
      merged.child_date_of_birth,
      merged.guardian_first_name,
      merged.guardian_last_name,
      merged.guardian_email,
      merged.guardian2_first_name,
      merged.guardian2_last_name,
      merged.guardian2_email,
      merged.school_grade,
      merged.school_name,
      merged.has_medical,
      merged.medical_conditions,
      merged.nut_allergy,
      merged.consent_photo_marketing,
      merged.consent_photo_social_media,
      merged.program_name,
      merged.instructor_name,
      merged.season
    ]
  end
end
