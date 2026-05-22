defmodule KlassHeroWeb.Provider.EnrollmentImportControllerIntegrationTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.Factory

  alias KlassHero.Enrollment.Adapters.Driven.Persistence.Schemas.BulkEnrollmentInviteSchema

  @moduletag :integration

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

  defp write_tmp_csv(content) do
    path = Path.join(System.tmp_dir!(), "test_import_#{System.unique_integer([:positive])}.csv")
    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp upload(path) do
    %Plug.Upload{
      path: path,
      filename: "import.csv",
      content_type: "text/csv"
    }
  end

  # -- tests -----------------------------------------------------------------

  describe "POST /provider/enrollment/import (5k rows)" do
    test "imports 5000 rows in a single transaction" do
      %{conn: conn, provider: provider} = register_and_log_in_provider(%{conn: build_conn()})
      insert(:program_schema, provider_id: provider.id, title: "Ballsports & Parkour")

      rows =
        for i <- 1..5_000 do
          %{
            first: "Child#{i}",
            last: "Last#{i}",
            email: "parent#{i}@test.com",
            program: "Ballsports & Parkour"
          }
        end

      csv = build_csv(rows)
      path = write_tmp_csv(csv)

      conn = post(conn, ~p"/provider/enrollment/import", %{"file" => upload(path)})

      assert json_response(conn, 201) == %{"created" => 5_000, "failed" => []}
      assert KlassHero.Repo.aggregate(BulkEnrollmentInviteSchema, :count) == 5_000
    end
  end
end
