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

  # Custom parser so we can pass skip_headers: false and control header handling ourselves
  NimbleCSV.define(__MODULE__.Parser, separator: ",", escape: "\"")

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
    * `{:error, message}` — row-level parse failure (bad date, blank line,
      etc.)
    * `{:parse_halt, message}` — structural CSV failure (mid-stream
      `NimbleCSV.ParseError`). Stream consumers should treat this as a
      signal to halt further processing; subsequent stream elements
      after a `:parse_halt` are undefined.

  Whole-file fatals (empty CSV, malformed header, missing headers) do
  NOT appear here — they are produced by `validate_headers/1` before any
  streaming begins.

  ## Row numbering is caller-owned

  This stream does NOT tag elements with row numbers. Callers thread
  positional context via `Stream.with_index/2`, choosing their own base
  (e.g. `2` for user-visible CSV line numbers that count the header as
  row 1):

      prepared
      |> CsvParser.parse_stream()
      |> Stream.with_index(2)
      |> Enum.each(fn {element, file_row} -> ... end)

  Blank lines ARE emitted as `{:error, "blank row"}` rather than being
  silently skipped, so positional indexing stays aligned with the file's
  data-row positions even when blanks are present.

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
            | {:error, String.t()}
            | {:parse_halt, String.t()}
          )
  def parse_stream(%{column_keys: column_keys, remainder: remainder}) do
    col_count = length(column_keys)

    [remainder]
    |> __MODULE__.Parser.to_line_stream()
    |> __MODULE__.Parser.parse_stream(skip_headers: false)
    |> with_halt_on_raise()
    |> Stream.map(fn
      {:parse_halt, message} ->
        {:parse_halt, message}

      cells when is_list(cells) ->
        process_row(cells, column_keys, col_count)
    end)
  end

  defp process_row(cells, column_keys, col_count) do
    if blank_row?(cells) do
      {:error, "blank row"}
    else
      padded = pad_cells(cells, col_count)
      build_row(padded, column_keys)
    end
  end

  # A blank line yields a single empty-string cell from NimbleCSV. We treat
  # those as a row-level error (not a fatal halt) so row numbering stays
  # aligned with the user's spreadsheet without misclassifying intentionally
  # empty rows.
  defp blank_row?([""]), do: true
  defp blank_row?([cell]) when is_binary(cell), do: String.trim(cell) == ""
  defp blank_row?(_), do: false

  # NimbleCSV.parse_stream/2 raises mid-stream on malformed cells; a downstream
  # try/rescue can't catch that because the raise is in the producer. Wrapping here
  # converts the raise into a {:parse_halt, msg} sentinel at the producer boundary.
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

  Row numbers in the error list are 2-based (header is row 1), applied
  here via `Stream.with_index/2`. `parse_stream/1` itself does not tag
  rows — see its `@doc` for details on caller-owned numbering.

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
      |> Stream.with_index(2)
      |> Enum.to_list()
      |> case do
        [] -> {:error, :empty_csv}
        results -> partition_results(results)
      end
    end
  end

  # reduce_while stops on the first :parse_halt so exactly one error is emitted, not N
  defp partition_results(results) do
    {oks, errs} =
      Enum.reduce_while(results, {[], []}, fn
        {{:ok, row}, _file_row}, {oks, errs} ->
          {:cont, {[row | oks], errs}}

        {{:error, msg}, file_row}, {oks, errs} ->
          {:cont, {oks, [{file_row, msg} | errs]}}

        {{:parse_halt, msg}, file_row}, {oks, errs} ->
          {:halt, {oks, [{file_row, "CSV file is malformed: #{msg}"} | errs]}}
      end)

    case {Enum.reverse(oks), Enum.reverse(errs)} do
      {rows, []} -> {:ok, rows}
      {_rows, errors} -> {:error, errors}
    end
  end

  # Google Sheets and Excel (Android) prepend a UTF-8 BOM that corrupts the first header
  defp strip_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: rest
  defp strip_bom(text), do: text

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

  defp pad_cells(cells, expected_count) do
    actual = length(cells)

    if actual < expected_count do
      cells ++ List.duplicate("", expected_count - actual)
    else
      cells
    end
  end

  defp build_row(cells, column_keys) do
    pairs =
      column_keys
      |> Enum.zip(cells)
      |> Enum.reject(fn {key, _val} -> key == :skip or is_nil(key) end)

    Enum.reduce_while(pairs, {:ok, %{}}, fn {key, raw_value}, {:ok, acc} ->
      case convert_value(key, raw_value) do
        {:ok, converted} -> {:cont, {:ok, Map.put(acc, key, converted)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp convert_value(:child_date_of_birth, raw) do
    parse_date(raw, :child_date_of_birth)
  end

  defp convert_value(key, raw) when key in [:nut_allergy, :consent_photo_marketing, :consent_photo_social_media] do
    {:ok, parse_boolean(raw)}
  end

  defp convert_value(:school_grade, raw) do
    parse_grade(raw)
  end

  defp convert_value(_key, raw) do
    {:ok, clean_string(raw)}
  end

  # Dates arrive as M/D/YYYY or MM/DD/YYYY from parent forms; row numbering is caller-owned via Stream.with_index/2
  defp parse_date(raw, field) do
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

  defp parse_boolean(raw) do
    raw
    |> String.trim()
    |> String.downcase()
    |> case do
      v when v in ["yes", "true", "1"] -> true
      _ -> false
    end
  end

  defp parse_grade(raw) do
    raw
    |> String.trim()
    |> Integer.parse()
    |> case do
      {grade, ""} -> {:ok, grade}
      _ -> {:ok, nil}
    end
  end

  defp clean_string(raw) do
    case String.trim(raw) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
