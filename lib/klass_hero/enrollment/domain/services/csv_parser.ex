defmodule KlassHero.Enrollment.Domain.Services.CsvParser do
  @moduledoc """
  Parses CSV binary into structured enrollment row maps.

  Pure domain service — no DB, no IO beyond NimbleCSV parsing.
  The CSV shape is fixed (program import template) with verbose headers
  that are mapped to concise internal atoms.

  ## Return Shape

      {:ok, [%{child_first_name: "...", ...}]}
      {:error, :empty_csv}
      {:error, :malformed_csv}
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
  Returns a lazy `Enumerable.t/0` over the prepared CSV remainder.

  Each yielded element is one of:

    * `{:ok, row_map}` — successfully parsed and type-converted row
    * `{:error, {row_num, message}}` — row-level parse failure (bad date,
      blank line, etc.)
    * `{:parse_halt, row_num, message}` — structural CSV failure (mid-stream
      `NimbleCSV.ParseError`). Stream consumers should treat this as a
      signal to halt further processing; subsequent stream elements
      after a `:parse_halt` are undefined.

  Whole-file fatals (empty CSV, malformed header, missing headers) do
  NOT appear here — they are produced by `validate_headers/1` before any
  streaming begins.

  Row numbers in every shape (`{:ok, _}`, `{:error, {n, _}}`,
  `{:parse_halt, n, _}`) are 1-based starting from the first data row
  (header line is NOT counted). Blank lines ARE counted so row numbers
  stay aligned with the file's data-row positions even when blanks are
  present.

  ## RFC4180 multi-line quoted fields

  Internally this pipes the remainder through `NimbleCSV`'s
  `to_line_stream/1` (which re-chunks on newlines while preserving
  quoted multi-line cells as a single row) and then `parse_stream/2`.
  Mid-stream parse errors raised by NimbleCSV are caught by a wrapping
  `Stream.resource/3` so they surface as the `:parse_halt` sentinel
  rather than crashing the caller.
  """
  @spec parse_stream(prepared()) ::
          Enumerable.t(
            {:ok, map()}
            | {:error, {pos_integer(), String.t()}}
            | {:parse_halt, pos_integer(), String.t()}
          )
  def parse_stream(%{column_keys: column_keys, remainder: remainder}) do
    col_count = length(column_keys)

    [remainder]
    |> __MODULE__.Parser.to_line_stream()
    |> __MODULE__.Parser.parse_stream(skip_headers: false)
    |> with_halt_on_raise()
    |> Stream.with_index(1)
    |> Stream.map(fn
      {{:parse_halt, message}, row_number} ->
        {:parse_halt, row_number, message}

      {cells, row_number} when is_list(cells) ->
        process_row(cells, row_number, column_keys, col_count)
    end)
  end

  defp process_row(cells, row_number, column_keys, col_count) do
    if blank_row?(cells) do
      {:error, {row_number, "blank row"}}
    else
      padded = pad_cells(cells, col_count)
      tag_row(build_row(padded, column_keys, row_number), row_number)
    end
  end

  defp tag_row({:ok, _} = ok, _row_number), do: ok
  defp tag_row({:error, reason}, row_number), do: {:error, {row_number, reason}}

  # A blank line yields a single empty-string cell from NimbleCSV. We treat
  # those as a row-level error (not a fatal halt) so row numbering stays
  # aligned with the user's spreadsheet without misclassifying intentionally
  # empty rows.
  defp blank_row?([""]), do: true
  defp blank_row?([cell]) when is_binary(cell), do: String.trim(cell) == ""
  defp blank_row?(_), do: false

  # Wraps an enumerable so that any exception raised during enumeration is
  # surfaced as a single trailing `{:parse_halt, msg}` element, after which
  # the wrapped stream is treated as exhausted.
  #
  # Trigger: NimbleCSV.parse_stream/2 raises NimbleCSV.ParseError mid-stream
  #   when it hits a structurally malformed cell (e.g. unbalanced quote).
  # Why: a raised exception inside a lazy pipeline cannot be caught by a
  #   downstream Stream.map's try/rescue — the raise happens in the producer.
  #   Wrapping at the producer boundary converts the raise into a
  #   well-known sentinel so the caller can preserve rows committed before
  #   the error and decide whether to keep going.
  # Outcome: a malformed CSV yields at most one `:parse_halt` followed by
  #   end-of-stream, never a runtime crash.
  defp with_halt_on_raise(stream) do
    Stream.resource(
      fn ->
        {:suspended, _, cont} =
          Enumerable.reduce(stream, {:suspend, nil}, fn item, _ -> {:suspend, item} end)

        {:cont, cont}
      end,
      fn
        :done ->
          {:halt, :done}

        {:cont, cont} ->
          try do
            case cont.({:cont, nil}) do
              {:suspended, item, next_cont} -> {[item], {:cont, next_cont}}
              {:done, _} -> {:halt, :done}
              {:halted, _} -> {:halt, :done}
            end
          rescue
            e in NimbleCSV.ParseError ->
              {[{:parse_halt, Exception.message(e)}], :done}
          end
      end,
      fn _ -> :ok end
    )
  end

  @doc """
  Parses a CSV binary into a list of rows (eager). Equivalent to
  `validate_headers/1` followed by `parse_stream/1`, partitioned into
  either all-ok or all-error.

  Kept for back-compat with callers that prefer a single return value.
  New callers should prefer the streaming pair for memory-bounded
  processing.
  """
  @spec parse(binary()) ::
          {:ok, [map()]}
          | {:error, :empty_csv}
          | {:error, :malformed_csv}
          | {:error, {:invalid_headers, [atom()]}}
          | {:error, [{pos_integer(), String.t()}]}
  def parse(csv) when is_binary(csv) do
    with {:ok, prepared} <- validate_headers(csv) do
      prepared
      |> parse_stream()
      |> Enum.to_list()
      |> case do
        [] -> {:error, :empty_csv}
        results -> partition_results(results)
      end
    end
  end

  # Trigger: parse_stream/1's sentinel contract states subsequent stream
  #   elements after a :parse_halt are undefined.
  # Why: an earlier Enum.reduce/3 would walk the WHOLE list, converting every
  #   :parse_halt-shaped element to a duplicate error. A single mid-stream
  #   structural break should surface as exactly one error tuple, not N.
  # Outcome: reduce_while halts on the first :parse_halt, attributing the
  #   error to the row number it actually occurred on.
  defp partition_results(results) do
    {oks, errs} =
      Enum.reduce_while(results, {[], []}, fn
        {:ok, row}, {oks, errs} ->
          {:cont, {[row | oks], errs}}

        {:error, {row_num, msg}}, {oks, errs} ->
          {:cont, {oks, [{row_num, msg} | errs]}}

        {:parse_halt, row_num, msg}, {oks, errs} ->
          {:halt, {oks, [{row_num, "CSV file is malformed: #{msg}"} | errs]}}
      end)

    case {Enum.reverse(oks), Enum.reverse(errs)} do
      {rows, []} -> {:ok, rows}
      {_rows, errors} -> {:error, errors}
    end
  end

  # Trigger: spreadsheet apps (Google Sheets, Excel on Android) prepend UTF-8 BOM
  # Why: the BOM bytes corrupt the first header, breaking column resolution
  # Outcome: BOM is silently removed so the parser sees clean UTF-8 text
  defp strip_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: rest
  defp strip_bom(text), do: text

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
  # Outcome: a %Date{} struct or an error scoped to the column and bad value

  # Trigger: per-cell converters used to embed `(row N)` in their error messages
  # Why: row numbers are already in the {row_num, message} tuple yielded by
  #      parse_stream/1; the use case owns canonical 2-based numbering (header
  #      is row 1), so double-numbering produced contradictory output
  # Outcome: messages stay column/value-specific; numbering happens at the boundary
  defp parse_date(raw, field, _row_number) do
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
            {:error, "invalid date format in column #{field}: #{trimmed}"}
        end

      _ ->
        {:error, "invalid date format in column #{field}: #{trimmed}"}
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
