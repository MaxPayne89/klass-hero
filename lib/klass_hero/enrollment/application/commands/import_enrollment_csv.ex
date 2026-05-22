defmodule KlassHero.Enrollment.Application.Commands.ImportEnrollmentCsv do
  @moduledoc """
  Use case for importing enrollment invites from a CSV file.

  Streams rows through `CsvParser.parse_stream/1`, validates each
  independently, and inserts surviving rows one-by-one via
  `create_one/1`. Whole-file fatals (empty CSV, missing headers,
  no programs, title collisions) short-circuit and return
  `{:error, %{parse_errors: [...]}}`. Row-level failures are
  accumulated; the use case always returns `{:ok, %{created, failed}}`
  in that case.

  ## Return shape

      {:ok, %{
        created: non_neg_integer(),
        failed: [%{
          row: pos_integer() | nil,
          category: :parse | :validation | :duplicate | :insert,
          errors: String.t() | [{atom(), String.t()}]
        }]
      }}

      {:error, %{parse_errors: [{0, String.t()}]}}  # whole-file fatal
  """

  alias KlassHero.Enrollment.Application.ChangesetErrors
  alias KlassHero.Enrollment.Application.ProviderProgramContext
  alias KlassHero.Enrollment.Domain.Events.EnrollmentEvents
  alias KlassHero.Enrollment.Domain.Models.BulkEnrollmentInvite
  alias KlassHero.Enrollment.Domain.Services.CsvParser
  alias KlassHero.Enrollment.Domain.Services.ImportRowValidator
  alias KlassHero.Shared.EventDispatchHelper

  require Logger

  @invite_reader Application.compile_env!(:klass_hero, [
                   :enrollment,
                   :for_querying_bulk_enrollment_invites
                 ])
  @invite_repository Application.compile_env!(:klass_hero, [
                       :enrollment,
                       :for_storing_bulk_enrollment_invites
                     ])

  @default_chunk_size 100

  @type failure :: %{
          row: pos_integer() | nil,
          category: :parse | :validation | :duplicate | :insert,
          errors: String.t() | [{atom(), String.t()}]
        }

  @type report :: %{created: non_neg_integer(), failed: [failure()]}

  @spec execute(binary(), binary()) ::
          {:ok, report()} | {:error, %{parse_errors: [{0, String.t()}]}}
  def execute(provider_id, csv_binary), do: execute(provider_id, csv_binary, [])

  @spec execute(binary(), binary(), keyword()) ::
          {:ok, report()} | {:error, %{parse_errors: [{0, String.t()}]}}
  def execute(provider_id, csv_binary, opts) when is_binary(provider_id) and is_binary(csv_binary) and is_list(opts) do
    Logger.info("[ImportEnrollmentCsv] Starting CSV import for provider #{provider_id}")

    chunk_size = fetch_chunk_size(opts)

    with {:ok, prepared} <- prepare_csv(csv_binary),
         {:ok, context} <- build_context(provider_id) do
      existing_keys =
        @invite_reader.list_existing_keys_for_programs(context.all_program_ids)

      acc0 = %{
        created: 0,
        failed: [],
        seen: MapSet.new(),
        existing_keys: existing_keys,
        success_program_ids: MapSet.new(),
        context: context,
        next_row: 2
      }

      final =
        prepared
        |> CsvParser.parse_stream()
        |> Stream.chunk_every(chunk_size)
        |> Enum.reduce_while(acc0, &process_chunk/2)

      Logger.info(
        "[ImportEnrollmentCsv] Finished for provider #{provider_id}: " <>
          "created=#{final.created} failed=#{length(final.failed)}"
      )

      maybe_publish_event(provider_id, final)

      {:ok, %{created: final.created, failed: Enum.reverse(final.failed)}}
    end
  end

  # -- whole-file fatals -----------------------------------------------------

  defp prepare_csv(csv_binary) do
    case CsvParser.validate_headers(csv_binary) do
      {:ok, prepared} ->
        {:ok, prepared}

      {:error, :empty_csv} ->
        {:error, %{parse_errors: [{0, "CSV file is empty or has no data rows"}]}}

      {:error, :malformed_csv} ->
        {:error, %{parse_errors: [{0, "CSV file is malformed at the header row"}]}}

      {:error, {:invalid_headers, missing}} ->
        {:error, %{parse_errors: [{0, "Missing required columns: #{inspect(missing)}"}]}}
    end
  end

  defp build_context(provider_id) do
    case ProviderProgramContext.for_provider(provider_id) do
      {:ok, context} ->
        # Enrich context with a flat list of all program IDs so the
        # existing-keys preload query has what it needs.
        {:ok, Map.put(context, :all_program_ids, Map.values(context.programs_by_title))}

      {:error, :no_programs} ->
        {:error,
         %{
           parse_errors: [
             {0, "No programs found for this provider. Create programs before importing."}
           ]
         }}

      {:error, {:title_collisions, titles}} ->
        msg =
          "Program titles must be unique ignoring case. Conflicting titles: " <>
            Enum.join(titles, ", ")

        {:error, %{parse_errors: [{0, msg}]}}
    end
  end

  # -- chunk + per-row dispatch ------------------------------------------------

  defp process_chunk(chunk, acc) do
    Enum.reduce_while(chunk, {:cont, acc}, fn
      {:parse_halt, _stream_row_num, message}, {_, acc} ->
        # The use case owns canonical 2-based numbering (header is row 1),
        # so we surface the data-row index from acc.next_row rather than the
        # parser's 1-based stream index.
        halt_entry = %{
          row: acc.next_row,
          category: :parse,
          errors: "Stream halted: #{message}"
        }

        {:halt, {:halt, push_failure(acc, halt_entry)}}

      row_result, {_, acc} ->
        {:cont, {:cont, process_row(row_result, acc)}}
    end)
  end

  # Row-level parse error from CsvParser.parse_stream/1 (e.g. bad date format).
  # Capture row number from acc BEFORE bumping — next_row is the current data row.
  defp process_row({:error, {_stream_row_num, message}}, acc) do
    acc
    |> push_failure(%{row: acc.next_row, category: :parse, errors: message})
    |> Map.update!(:next_row, &(&1 + 1))
  end

  defp process_row({:ok, row}, acc) do
    row_num = acc.next_row
    acc = Map.update!(acc, :next_row, &(&1 + 1))

    case ImportRowValidator.validate(row, acc.context) do
      {:error, field_errors} ->
        push_failure(acc, %{row: row_num, category: :validation, errors: field_errors})

      {:ok, validated_row} ->
        attempt_dedup_and_insert(validated_row, row_num, acc)
    end
  end

  defp attempt_dedup_and_insert(row, row_num, acc) do
    key = dedup_key(row)

    cond do
      MapSet.member?(acc.seen, key) ->
        push_failure(acc, %{
          row: row_num,
          category: :duplicate,
          errors: "Duplicate entry in CSV: same program, guardian email, and child name"
        })

      MapSet.member?(acc.existing_keys, key) ->
        acc
        |> Map.update!(:seen, &MapSet.put(&1, key))
        |> push_failure(%{
          row: row_num,
          category: :duplicate,
          errors: "Invite already exists for this child and program"
        })

      true ->
        case @invite_repository.create_one(row) do
          {:ok, _invite} ->
            %{
              acc
              | created: acc.created + 1,
                seen: MapSet.put(acc.seen, key),
                success_program_ids: MapSet.put(acc.success_program_ids, row.program_id)
            }

          {:error, %Ecto.Changeset{} = changeset} ->
            acc
            |> Map.update!(:seen, &MapSet.put(&1, key))
            |> push_failure(%{
              row: row_num,
              category: :insert,
              errors: ChangesetErrors.field_list(changeset)
            })
        end
    end
  end

  defp push_failure(acc, failure) do
    Map.update!(acc, :failed, &[failure | &1])
  end

  defp dedup_key(row) do
    BulkEnrollmentInvite.dedup_key(
      row.program_id,
      row.guardian_email,
      row.child_first_name,
      row.child_last_name
    )
  end

  defp fetch_chunk_size(opts) do
    case Keyword.get(opts, :chunk_size, @default_chunk_size) do
      n when is_integer(n) and n > 0 -> n
      bad -> raise ArgumentError, "chunk_size must be a positive integer, got: #{inspect(bad)}"
    end
  end

  defp maybe_publish_event(_provider_id, %{created: 0}), do: :ok

  defp maybe_publish_event(provider_id, %{created: count, success_program_ids: ids}) do
    EnrollmentEvents.bulk_invites_imported(provider_id, MapSet.to_list(ids), count)
    |> EventDispatchHelper.dispatch(KlassHero.Enrollment)
  end
end
