defmodule KlassHero.Enrollment.Domain.Services.CsvParser do
  @moduledoc """
  Parses CSV binary into structured enrollment row maps.

  Pure domain service — no DB, no IO beyond NimbleCSV parsing.
  The CSV shape is fixed (program import template) with verbose headers
  that are mapped to concise internal atoms.

  ## Return Shape

      {:ok, [%{child_first_name: "...", ...}]}
      {:error, :empty_csv}
      {:error, {:invalid_headers, [:child_first_name, ...]}}
      {:error, [{row_number, "reason"}]}
  """

  # -- custom NimbleCSV parser ------------------------------------------------
  # Trigger: need to keep headers for column mapping
  # Why: NimbleCSV.RFC4180 skips headers by default and we can't control it
  #      without skip_headers: false, but we need to parse headers + data together
  # Outcome: custom parser gives us full control over header handling
  NimbleCSV.define(__MODULE__.Parser, separator: ",", escape: "\"")

  # -- header → atom mapping -------------------------------------------------
  # Trigger: CSV headers are verbose and may vary slightly in formatting
  # Why: prefix matching is more robust than exact string comparison
  # Outcome: each header maps to an internal atom, or :skip for ignored columns

  @header_mappings [
    {"Participant information: First", :child_first_name},
    {"Participant information: Last", :child_last_name},
    {"Participant information: Date", :child_date_of_birth},
    {"Parent/guardian information: First", :guardian_first_name},
    {"Parent/guardian information: Last", :guardian_last_name},
    {"Parent/guardian information: Email", :guardian_email},
    {"Parent/guardian 2 information: First", :guardian2_first_name},
    {"Parent/guardian 2 information: Last", :guardian2_last_name},
    {"Parent/guardian 2 information: Email", :guardian2_email},
    {"School information: Grade", :school_grade},
    {"School information: Name", :school_name},
    {"Medical/allergy information: Do you have", :skip},
    {"Medical/allergy information: Medical", :medical_conditions},
    {"Medical/allergy information: Nut", :nut_allergy},
    {"Photography/video release permission: I agree that photos showing", :consent_photo_marketing},
    {"Photography/video release permission: I agree that photos and films", :consent_photo_social_media},
    {"Program", :program_name},
    {"Instructor", :instructor_name},
    {"Season", :season}
  ]

  @required_keys @header_mappings
                 |> Enum.map(&elem(&1, 1))
                 |> Enum.reject(&(&1 == :skip))

  # -- public API ------------------------------------------------------------

  @type prepared :: %{column_keys: [atom() | :skip | nil], remainder: binary()}

  @doc """
  Eagerly peeks at the first line of the CSV binary, resolves headers to
  column keys, and returns a prepared payload ready to be streamed by
  `parse_stream/1`. Strips a leading UTF-8 BOM if present.

  This is the ONLY place that produces whole-file fatals
  (`:empty_csv`, `:malformed_csv`, `{:invalid_headers, missing}`).
  `parse_stream/1` then assumes headers are valid and never short-circuits
  on header issues.
  """
  @spec validate_headers(binary()) ::
          {:ok, prepared()}
          | {:error, :empty_csv}
          | {:error, :malformed_csv}
          | {:error, {:invalid_headers, [atom()]}}
  def validate_headers(csv) when is_binary(csv) do
    trimmed =
      csv
      |> strip_bom()
      |> String.trim_leading()

    case String.split(trimmed, ~r/\r?\n/, parts: 2) do
      [""] ->
        {:error, :empty_csv}

      [only_header] ->
        with {:ok, keys} <- parse_header_line(only_header) do
          {:ok, %{column_keys: keys, remainder: ""}}
        end

      [header_line, remainder] ->
        with {:ok, keys} <- parse_header_line(header_line) do
          {:ok, %{column_keys: keys, remainder: remainder}}
        end
    end
  end

  defp parse_header_line(header_line) do
    case __MODULE__.Parser.parse_string(header_line, skip_headers: false) do
      [raw_headers | _] -> resolve_headers(raw_headers)
      [] -> {:error, :empty_csv}
    end
  rescue
    _e in NimbleCSV.ParseError ->
      {:error, :malformed_csv}
  end

  @doc """
  Parses a CSV binary string into a list of structured row maps.

  Returns `{:ok, rows}` when all rows parse successfully, or
  `{:error, reason}` when the CSV is empty, has invalid headers,
  or contains rows with unparseable values.
  """
  @spec parse(binary()) ::
          {:ok, [map()]}
          | {:error, :empty_csv}
          | {:error, {:invalid_headers, [atom()]}}
          | {:error, [{pos_integer(), String.t()}]}
  def parse(csv) when is_binary(csv) do
    trimmed =
      csv
      |> strip_bom()
      |> String.trim()

    if trimmed == "" do
      {:error, :empty_csv}
    else
      do_parse(trimmed)
    end
  end

  # Trigger: spreadsheet apps (Google Sheets, Excel on Android) prepend UTF-8 BOM
  # Why: the BOM bytes corrupt the first header, breaking column resolution
  # Outcome: BOM is silently removed so the parser sees clean UTF-8 text
  defp strip_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: rest
  defp strip_bom(text), do: text

  # -- internal pipeline -----------------------------------------------------

  defp do_parse(csv) do
    # Trigger: need to extract headers and data rows from the same CSV
    # Why: NimbleCSV handles quoting/escaping correctly for both headers and data
    # Outcome: first row becomes header mapping, remaining rows become structured maps
    all_rows =
      try do
        __MODULE__.Parser.parse_string(csv, skip_headers: false)
      rescue
        # Trigger: malformed CSV input (mismatched quotes, stray escapes)
        # Why: NimbleCSV raises on structural errors; callers expect {:error, _} tuples
        # Outcome: surface a descriptive error instead of crashing
        e in NimbleCSV.ParseError ->
          {:error, [{1, "CSV file is malformed: #{Exception.message(e)}"}]}
      end

    case all_rows do
      {:error, _} = error ->
        error

      [] ->
        {:error, :empty_csv}

      [headers] ->
        # Only headers, no data rows
        with {:ok, _column_keys} <- resolve_headers(headers) do
          {:error, :empty_csv}
        end

      [headers | data_rows] ->
        with {:ok, column_keys} <- resolve_headers(headers) do
          col_count = length(column_keys)
          build_rows(data_rows, column_keys, col_count)
        end
    end
  end

  # -- header resolution -----------------------------------------------------

  defp resolve_headers(raw_headers) do
    mapped =
      Enum.map(raw_headers, fn header ->
        trimmed = String.trim(header)
        find_mapping(trimmed)
      end)

    found_keys = mapped |> Enum.reject(&(&1 in [nil, :skip])) |> MapSet.new()
    missing = Enum.reject(@required_keys, &MapSet.member?(found_keys, &1))

    if missing == [] do
      {:ok, mapped}
    else
      {:error, {:invalid_headers, missing}}
    end
  end

  defp find_mapping(header) do
    Enum.find_value(@header_mappings, fn {prefix, key} ->
      if String.starts_with?(header, prefix), do: key
    end)
  end

  # -- row building ----------------------------------------------------------

  defp build_rows(raw_rows, column_keys, col_count) do
    {rows, errors} =
      raw_rows
      |> Enum.with_index(2)
      |> Enum.reduce({[], []}, fn {cells, row_number}, {good, bad} ->
        # Trigger: NimbleCSV drops trailing empty cells
        # Why: a row like "a,b,,," becomes ["a","b"] instead of ["a","b","",""]
        # Outcome: pad with empty strings so zip aligns correctly with column_keys
        padded_cells = pad_cells(cells, col_count)

        case build_row(padded_cells, column_keys, row_number) do
          {:ok, row} -> {[row | good], bad}
          {:error, reason} -> {good, [{row_number, reason} | bad]}
        end
      end)

    if errors == [] do
      {:ok, Enum.reverse(rows)}
    else
      {:error, Enum.reverse(errors)}
    end
  end

  defp pad_cells(cells, expected_count) do
    actual = length(cells)

    if actual < expected_count do
      cells ++ List.duplicate("", expected_count - actual)
    else
      cells
    end
  end

  defp build_row(cells, column_keys, row_number) do
    pairs =
      column_keys
      |> Enum.zip(cells)
      |> Enum.reject(fn {key, _val} -> key == :skip or is_nil(key) end)

    Enum.reduce_while(pairs, {:ok, %{}}, fn {key, raw_value}, {:ok, acc} ->
      case convert_value(key, raw_value, row_number) do
        {:ok, converted} -> {:cont, {:ok, Map.put(acc, key, converted)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  # -- type conversions ------------------------------------------------------

  # Trigger: each column has a known type based on its key
  # Why: raw CSV values are all strings; domain expects typed values
  # Outcome: strings become dates, booleans, integers, or trimmed/nilled strings

  defp convert_value(:child_date_of_birth, raw, row_number) do
    parse_date(raw, :child_date_of_birth, row_number)
  end

  defp convert_value(key, raw, _row_number)
       when key in [:nut_allergy, :consent_photo_marketing, :consent_photo_social_media] do
    {:ok, parse_boolean(raw)}
  end

  defp convert_value(:school_grade, raw, row_number) do
    parse_grade(raw, row_number)
  end

  defp convert_value(_key, raw, _row_number) do
    {:ok, clean_string(raw)}
  end

  # -- date parsing ----------------------------------------------------------
  # Trigger: dates arrive as M/D/YYYY or MM/DD/YYYY
  # Why: parents fill forms with inconsistent date formatting
  # Outcome: a %Date{} struct or an error with row context

  defp parse_date(raw, field, row_number) do
    trimmed = String.trim(raw)

    case String.split(trimmed, "/") do
      [month, day, year] ->
        with {m, ""} <- Integer.parse(month),
             {d, ""} <- Integer.parse(day),
             {y, ""} <- Integer.parse(year),
             {:ok, date} <- Date.new(y, m, d) do
          {:ok, date}
        else
          _ ->
            {:error, "invalid date format in column #{field}: #{trimmed} (row #{row_number})"}
        end

      _ ->
        {:error, "invalid date format in column #{field}: #{trimmed} (row #{row_number})"}
    end
  end

  # -- boolean parsing -------------------------------------------------------

  defp parse_boolean(raw) do
    # Trigger: CSV exports may use varying boolean representations
    # Why: case-insensitive matching avoids silent data loss from "yes" vs "Yes"
    # Outcome: "yes", "true", "1" (any case) → true; everything else → false
    raw
    |> String.trim()
    |> String.downcase()
    |> case do
      v when v in ["yes", "true", "1"] -> true
      _ -> false
    end
  end

  # -- grade parsing ---------------------------------------------------------

  defp parse_grade(raw, _row_number) do
    raw
    |> String.trim()
    |> Integer.parse()
    |> case do
      {grade, ""} -> {:ok, grade}
      _ -> {:ok, nil}
    end
  end

  # -- string cleaning -------------------------------------------------------

  defp clean_string(raw) do
    case String.trim(raw) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
