defmodule KlassHeroWeb.Provider.EnrollmentImportControllerTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.Factory

  alias KlassHero.Enrollment.BulkEnrollmentInvite

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

  defp write_temp(content) do
    path = Path.join(System.tmp_dir!(), "import_#{System.unique_integer([:positive])}.csv")
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

  describe "POST /provider/enrollment/import" do
    test "unauthenticated request redirects to login" do
      conn = build_conn()
      conn = post(conn, ~p"/provider/enrollment/import", %{"file" => "dummy"})

      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "user without provider profile receives 403", %{conn: conn} do
      # Log in a regular user (no provider profile)
      user = KlassHero.AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)

      csv = build_csv([%{}])
      path = write_temp(csv)

      conn = post(conn, ~p"/provider/enrollment/import", %{"file" => upload(path)})

      assert json_response(conn, 403) == %{"error" => "Provider profile required"}
    end

    test "no file uploaded returns 400" do
      %{conn: conn} = register_and_log_in_provider(%{conn: build_conn()})

      conn = post(conn, ~p"/provider/enrollment/import", %{})

      assert json_response(conn, 400) == %{"error" => "No file uploaded"}
    end

    test "returns 201 with created count and empty failed list for fully-valid CSV" do
      %{conn: conn, provider: provider} = register_and_log_in_provider(%{conn: build_conn()})
      insert(:program_schema, provider_id: provider.id, title: "Ballsports & Parkour")

      csv =
        build_csv([
          %{first: "Alice", last: "Smith", email: "alice@test.com"},
          %{first: "Bob", last: "Jones", email: "bob@test.com"}
        ])

      path = write_temp(csv)

      conn = post(conn, ~p"/provider/enrollment/import", %{"file" => upload(path)})

      assert json_response(conn, 201) == %{"created" => 2, "failed" => []}
    end

    test "returns 200 with mixed outcomes when some rows fail" do
      %{conn: conn, provider: provider} = register_and_log_in_provider(%{conn: build_conn()})
      insert(:program_schema, provider_id: provider.id, title: "Ballsports & Parkour")

      csv = build_csv([%{first: "Alice"}, %{first: "", email: "x@y.com"}])
      path = write_temp(csv)

      conn = post(conn, ~p"/provider/enrollment/import", %{"file" => upload(path)})

      body = json_response(conn, 200)
      assert body["created"] == 1
      assert [%{"row" => 3, "category" => "validation", "errors" => errors}] = body["failed"]
      assert errors["child_first_name"] == ["is required"]
    end

    test "returns 200 when all rows fail (created: 0, failed has all rows)" do
      %{conn: conn, provider: provider} = register_and_log_in_provider(%{conn: build_conn()})
      insert(:program_schema, provider_id: provider.id, title: "Ballsports & Parkour")

      csv = build_csv([%{first: ""}, %{first: "", email: "x@y.com"}])
      path = write_temp(csv)

      conn = post(conn, ~p"/provider/enrollment/import", %{"file" => upload(path)})

      body = json_response(conn, 200)
      assert body["created"] == 0
      assert length(body["failed"]) == 2
      assert Enum.all?(body["failed"], &(&1["category"] == "validation"))
    end

    test "returns 422 with parse_errors for whole-file fatal (empty CSV)" do
      %{conn: conn} = register_and_log_in_provider(%{conn: build_conn()})

      path = write_temp("")

      conn = post(conn, ~p"/provider/enrollment/import", %{"file" => upload(path)})

      body = json_response(conn, 422)
      assert %{"errors" => %{"parse_errors" => [%{"row" => 0, "message" => msg}]}} = body
      assert msg =~ "empty"
    end

    test "returns 422 with parse_errors for invalid CSV headers" do
      %{conn: conn} = register_and_log_in_provider(%{conn: build_conn()})

      path = write_temp("Wrong,Headers\nval1,val2\n")

      conn = post(conn, ~p"/provider/enrollment/import", %{"file" => upload(path)})

      body = json_response(conn, 422)
      assert %{"errors" => %{"parse_errors" => [%{"row" => _, "message" => msg}]}} = body
      assert msg =~ "Missing required columns"
    end

    test "BOM-prefixed CSV imports successfully" do
      %{conn: conn, provider: provider} = register_and_log_in_provider(%{conn: build_conn()})
      insert(:program_schema, provider_id: provider.id, title: "Ballsports & Parkour")

      bom = <<0xEF, 0xBB, 0xBF>>
      csv = bom <> build_csv([%{first: "Alice", last: "Smith", email: "alice@test.com"}])
      path = write_temp(csv)

      conn = post(conn, ~p"/provider/enrollment/import", %{"file" => upload(path)})

      body = json_response(conn, 201)
      assert body["created"] == 1
      assert body["failed"] == []
    end

    test "file exceeding 2MB returns 413" do
      %{conn: conn} = register_and_log_in_provider(%{conn: build_conn()})

      content = String.duplicate("x", 2_000_001)
      path = write_temp(content)

      conn = post(conn, ~p"/provider/enrollment/import", %{"file" => upload(path)})

      assert json_response(conn, 413) == %{"error" => "File too large (max 2MB)"}
    end
  end

  # 5k rows is :slow even in manual mode. See test/test_helper.exs for what opts it back in.
  describe "POST /provider/enrollment/import (5k rows)" do
    @tag :slow
    test "imports 5000 rows and enqueues one invite email each" do
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

      path = rows |> build_csv() |> write_temp()

      # `testing: :inline` would run all 5000 SendInviteEmailWorker jobs inside the enqueue's
      # own transaction — ~15k serialized queries on one connection, which crosses the
      # connection timeout on a slow runner (#1282). Manual mode inserts them as rows instead.
      conn =
        Oban.Testing.with_testing_mode(:manual, fn ->
          post(conn, ~p"/provider/enrollment/import", %{"file" => upload(path)})
        end)

      assert json_response(conn, 201) == %{"created" => 5_000, "failed" => []}
      assert KlassHero.Repo.aggregate(BulkEnrollmentInvite, :count) == 5_000
      assert KlassHero.Repo.aggregate(Oban.Job, :count) == 5_000
    end
  end
end
