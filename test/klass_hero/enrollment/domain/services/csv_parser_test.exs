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

  describe "date parsing" do
    test "parses M/D/YYYY format" do
      csv =
        build_csv([
          row_with_overrides(child_date_of_birth: "1/1/2016")
        ])

      assert {:ok, [row]} = CsvParser.parse(csv)
      assert row.child_date_of_birth == ~D[2016-01-01]
    end

    test "parses MM/DD/YYYY format" do
      csv =
        build_csv([
          row_with_overrides(child_date_of_birth: "09/23/2017")
        ])

      assert {:ok, [row]} = CsvParser.parse(csv)
      assert row.child_date_of_birth == ~D[2017-09-23]
    end

    test "parses mixed date formats correctly" do
      csv =
        build_csv([
          row_with_overrides(child_date_of_birth: "1/31/2017"),
          row_with_overrides(child_date_of_birth: "03/09/2018"),
          row_with_overrides(child_date_of_birth: "12/17/2015")
        ])

      assert {:ok, rows} = CsvParser.parse(csv)
      assert Enum.at(rows, 0).child_date_of_birth == ~D[2017-01-31]
      assert Enum.at(rows, 1).child_date_of_birth == ~D[2018-03-09]
      assert Enum.at(rows, 2).child_date_of_birth == ~D[2015-12-17]
    end
  end

  describe "boolean mapping" do
    test "Yes maps to true" do
      csv =
        build_csv([
          row_with_overrides(nut_allergy: "Yes", consent_photo_marketing: "Yes")
        ])

      assert {:ok, [row]} = CsvParser.parse(csv)
      assert row.nut_allergy == true
      assert row.consent_photo_marketing == true
    end

    test "No maps to false" do
      csv =
        build_csv([
          row_with_overrides(nut_allergy: "No", consent_photo_marketing: "No")
        ])

      assert {:ok, [row]} = CsvParser.parse(csv)
      assert row.nut_allergy == false
      assert row.consent_photo_marketing == false
    end

    test "empty string maps to false" do
      csv =
        build_csv([
          row_with_overrides(nut_allergy: "", consent_photo_marketing: "")
        ])

      assert {:ok, [row]} = CsvParser.parse(csv)
      assert row.nut_allergy == false
      assert row.consent_photo_marketing == false
    end

    test "handles case-insensitive truthy values" do
      for truthy <- ["yes", "YES", "Yes", "True", "true", "1"] do
        csv = build_csv([row_with_overrides(nut_allergy: truthy)])

        assert {:ok, [row]} = CsvParser.parse(csv),
               "expected #{inspect(truthy)} to parse successfully"

        assert row.nut_allergy == true,
               "expected #{inspect(truthy)} to map to true, got #{inspect(row.nut_allergy)}"
      end
    end

    test "handles case-insensitive falsy values" do
      for falsy <- ["No", "no", "NO", ""] do
        csv = build_csv([row_with_overrides(nut_allergy: falsy)])

        assert {:ok, [row]} = CsvParser.parse(csv),
               "expected #{inspect(falsy)} to parse successfully"

        assert row.nut_allergy == false,
               "expected #{inspect(falsy)} to map to false, got #{inspect(row.nut_allergy)}"
      end
    end
  end

  describe "grade parsing" do
    test "numeric string maps to integer" do
      csv = build_csv([row_with_overrides(school_grade: "3")])

      assert {:ok, [row]} = CsvParser.parse(csv)
      assert row.school_grade == 3
    end

    test "empty string maps to nil" do
      csv = build_csv([row_with_overrides(school_grade: "")])

      assert {:ok, [row]} = CsvParser.parse(csv)
      assert row.school_grade == nil
    end
  end

  describe "string handling" do
    test "trims whitespace from strings" do
      csv = build_csv([row_with_overrides(child_first_name: "Maxim ")])

      assert {:ok, [row]} = CsvParser.parse(csv)
      assert row.child_first_name == "Maxim"
    end

    test "converts empty strings to nil" do
      csv = build_csv([row_with_overrides(school_name: "", instructor_name: "")])

      assert {:ok, [row]} = CsvParser.parse(csv)
      assert row.school_name == nil
      assert row.instructor_name == nil
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
      csv = "\"unclosed quote,value\n"
      assert {:error, [{1, "CSV file is malformed:" <> _}]} = CsvParser.parse(csv)
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

      assert is_list(keys)
      assert :child_first_name in keys
      assert :program_name in keys
      assert is_binary(rest)
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

    test "yields {:error, {row_num, message}} for rows with bad data" do
      csv =
        build_csv_with_rows([
          "Alice,Smith,1/1/2016,Bob,Smith,bob@x.com,,,,,,,,,,,Ballsports,,Spring",
          "Carol,Doe,not-a-date,Dan,Doe,dan@x.com,,,,,,,,,,,Arts,,Spring",
          "Eve,Jones,3/3/2018,Frank,Jones,frank@x.com,,,,,,,,,,,Sports,,Spring"
        ])

      {:ok, prepared} = CsvParser.validate_headers(csv)
      results = prepared |> CsvParser.parse_stream() |> Enum.to_list()

      assert [
               {:ok, %{child_first_name: "Alice"}},
               {:error, {2, msg}},
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
