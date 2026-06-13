defmodule KlassHero.Enrollment.Domain.Services.ImportRowValidator do
  @moduledoc """
  Validates a single parsed CSV row against business rules.

  Pure domain service — no DB, no Ecto. Takes maps, returns maps/tuples.
  Receives the output of `CsvParser.parse/1` (a row map) plus a context map
  containing provider_id and a program title → ID lookup table.

  ## Validations (in order)

  1. Required fields present and non-empty
  2. Email format for guardian_email (and guardian2_email if present)
  3. Program existence in the context lookup table
  4. Date of birth is in the past
  5. School grade in 1..13 when present

  All validations run regardless of earlier failures — errors are accumulated.

  ## Return Shape

      {:ok, enriched_row}       # row with :program_id, :provider_id added;
                                # :program_name, :instructor_name, :season removed
      {:error, [{field, msg}]}  # all validation errors for the row
  """

  @email_regex ~r/^[^@,;\s]+@[^@,;\s]+$/

  @required_fields ~w(child_first_name child_last_name child_date_of_birth guardian_email program_name)a

  # program_name is resolved to program_id; instructor_name and season are lookup-only context
  @transient_fields ~w(program_name instructor_name season)a

  @spec validate(map(), map()) :: {:ok, map()} | {:error, [{atom(), String.t()}]}
  def validate(row, context) when is_map(row) and is_map(context) do
    errors = validate_row(row, context)

    if errors == [] do
      {:ok, enrich_row(row, context)}
    else
      {:error, errors}
    end
  end

  defp validate_row(row, context) do
    []
    |> validate_required(row)
    |> validate_email_format(row)
    |> validate_program_exists(row, context)
    |> validate_date_of_birth(row)
    |> validate_school_grade(row)
  end

  defp validate_required(errors, row) do
    Enum.reduce(@required_fields, errors, fn field, acc ->
      case Map.get(row, field) do
        nil -> [{field, "is required"} | acc]
        "" -> [{field, "is required"} | acc]
        _ -> acc
      end
    end)
  end

  defp validate_email_format(errors, row) do
    errors
    |> validate_single_email(:guardian_email, Map.get(row, :guardian_email))
    |> validate_optional_email(:guardian2_email, Map.get(row, :guardian2_email))
  end

  defp validate_single_email(errors, field, value) when is_binary(value) and value != "" do
    if Regex.match?(@email_regex, value) do
      errors
    else
      [{field, "must be a valid email"} | errors]
    end
  end

  defp validate_single_email(errors, _field, _value), do: errors

  defp validate_optional_email(errors, _field, nil), do: errors

  defp validate_optional_email(errors, field, value) when is_binary(value) and value != "" do
    if Regex.match?(@email_regex, value) do
      errors
    else
      [{field, "must be a valid email"} | errors]
    end
  end

  defp validate_optional_email(errors, _field, _value), do: errors

  defp validate_program_exists(errors, row, context) do
    program_name = Map.get(row, :program_name)

    cond do
      is_nil(program_name) or program_name == "" ->
        # Already caught by validate_required
        errors

      Map.has_key?(context.programs_by_title, String.downcase(program_name)) ->
        errors

      true ->
        [{:program_name, "program not found"} | errors]
    end
  end

  defp validate_date_of_birth(errors, row) do
    case Map.get(row, :child_date_of_birth) do
      %Date{} = dob ->
        if Date.before?(dob, Date.utc_today()) do
          errors
        else
          [{:child_date_of_birth, "must be in the past"} | errors]
        end

      _ ->
        # nil already caught by validate_required
        errors
    end
  end

  defp validate_school_grade(errors, row) do
    case Map.get(row, :school_grade) do
      nil ->
        errors

      grade when is_integer(grade) and grade >= 1 and grade <= 13 ->
        errors

      _invalid ->
        [{:school_grade, "must be between 1 and 13"} | errors]
    end
  end

  defp enrich_row(row, context) do
    {:ok, program_id} = Map.fetch(context.programs_by_title, String.downcase(row.program_name))

    row
    |> Map.put(:program_id, program_id)
    |> Map.put(:provider_id, context.provider_id)
    |> Map.drop(@transient_fields)
  end
end
