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
    invite_reader = invite_reader()
    invite_repository = invite_repository()

    with {:ok, prepared} <- prepare_csv(csv_binary),
         {:ok, context} <- build_context(provider_id) do
      acc0 = %{
        created: 0,
        failed: [],
        seen: MapSet.new(),
        existing_keys_by_program: %{},
        success_program_ids: MapSet.new(),
        context: context,
        next_row: 2,
        invite_reader: invite_reader,
        invite_repository: invite_repository
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

      if empty_csv?(final) do
        {:error, %{parse_errors: [{0, "CSV file is empty or has no data rows"}]}}
      else
        maybe_publish_event(provider_id, final)
        {:ok, %{created: final.created, failed: Enum.reverse(final.failed)}}
      end
    end
  end

  # -- runtime port resolution -----------------------------------------------

  # Trigger: tests / runtime swaps via Application.put_env need to be honored.
  # Why: compile_env! captures the binding at compile time, ignoring later
  #      Application.put_env calls — making port swapping in tests brittle.
  # Outcome: resolve ports at runtime so the active config always wins.
  defp invite_reader do
    Application.fetch_env!(:klass_hero, :enrollment)
    |> Keyword.fetch!(:for_querying_bulk_enrollment_invites)
  end

  defp invite_repository do
    Application.fetch_env!(:klass_hero, :enrollment)
    |> Keyword.fetch!(:for_storing_bulk_enrollment_invites)
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
        {:ok, context}

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

  # Trigger: header-only CSV (or header + only blank lines) reaches the reduce
  #          with no successful inserts and only blank-row parse failures (or
  #          no failures at all).
  # Why: CsvParser.validate_headers/1 accepts the header line, then
  #      parse_stream/1 yields zero {:ok, _} rows. Without this guard the use
  #      case would return {:ok, %{created: 0, failed: blanks}} — silently
  #      claiming success on a file that has no data.
  # Outcome: surface :empty_csv as a whole-file fatal so the UI can show the
  #          same error as a completely empty upload.
  defp empty_csv?(%{created: 0, failed: failed}) do
    Enum.all?(failed, &blank_row_failure?/1)
  end

  defp empty_csv?(_acc), do: false

  defp blank_row_failure?(%{category: :parse, errors: errors}) when is_binary(errors) do
    errors =~ "blank row"
  end

  defp blank_row_failure?(_), do: false

  # -- chunk + per-row dispatch ------------------------------------------------

  # Trigger: outer Enum.reduce_while needs {:cont, acc} | {:halt, acc}. The
  #          inner reduce_while also needs that shape but its accumulator
  #          carries the use-case state, so we'd be smushing two unrelated
  #          tag namespaces into one tuple.
  # Why: an earlier version returned the inner reduce's nested tuple by
  #      coincidence — refactoring the inner shape would silently break the
  #      outer fold. Using :continue/:halted internally separates the two.
  # Outcome: the inner accumulator tag (:continue/:halted) is mapped to the
  #          outer directive (:cont/:halt) in one explicit place.
  defp process_chunk(chunk, acc) do
    case Enum.reduce_while(chunk, {:continue, acc}, &process_row_in_chunk/2) do
      {:continue, new_acc} -> {:cont, new_acc}
      {:halted, new_acc} -> {:halt, new_acc}
    end
  end

  defp process_row_in_chunk({:parse_halt, _stream_row_num, message}, {_tag, acc}) do
    # The use case owns canonical 2-based numbering (header is row 1),
    # so we surface the data-row index from acc.next_row rather than the
    # parser's 1-based stream index.
    halt_entry = %{
      row: acc.next_row,
      category: :parse,
      errors: "Stream halted: #{message}"
    }

    {:halt, {:halted, push_failure(acc, halt_entry)}}
  end

  defp process_row_in_chunk(row_result, {_tag, acc}) do
    {:cont, {:continue, process_row(row_result, acc)}}
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

    if MapSet.member?(acc.seen, key) do
      push_failure(acc, %{
        row: row_num,
        category: :duplicate,
        errors: "Duplicate entry in CSV: same program, guardian email, and child name"
      })
    else
      {existing_dup?, acc} = check_existing_dup(acc, row, key)

      if existing_dup? do
        acc
        |> Map.update!(:seen, &MapSet.put(&1, key))
        |> push_failure(%{
          row: row_num,
          category: :duplicate,
          errors: "Invite already exists for this child and program"
        })
      else
        insert_row(acc, row, row_num, key)
      end
    end
  end

  defp insert_row(acc, row, row_num, key) do
    case acc.invite_repository.create_one(row) do
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

  # Trigger: per-row dedup check needs the set of existing DB keys for the
  #          row's program; loading all provider programs up front is wasteful
  #          when the CSV references only a few of them.
  # Why: a provider with 200 programs and a CSV touching 1 program would
  #      otherwise preload 200x more data than needed.
  # Outcome: lazy load on first reference, cache in the accumulator so later
  #          rows referencing the same program reuse the result.
  defp check_existing_dup(acc, row, key) do
    program_id = row.program_id

    case Map.fetch(acc.existing_keys_by_program, program_id) do
      {:ok, keys} ->
        {MapSet.member?(keys, key), acc}

      :error ->
        keys = acc.invite_reader.list_existing_keys_for_programs([program_id])
        acc = put_in(acc.existing_keys_by_program[program_id], keys)
        {MapSet.member?(keys, key), acc}
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
