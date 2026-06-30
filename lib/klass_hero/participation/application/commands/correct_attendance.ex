defmodule KlassHero.Participation.Application.Commands.CorrectAttendance do
  @moduledoc """
  Use case for correcting an attendance record.

  Two callers are supported via `:actor_role`:

  - `:admin` (default) — requires a `:reason`, which is appended to the
    appropriate notes field with an `[Admin correction]` prefix. Preserves
    the legacy admin behaviour.

  - `:provider` / `:staff` — `:reason` is optional. Notes the caller supplied
    via `:check_in_notes` / `:check_out_notes` replace the existing notes
    on the record (the edit *is* the audit trail; `updated_at` records when).
  """

  alias KlassHero.Participation.ParticipationRecord

  @participation_reader Application.compile_env!(
                          :klass_hero,
                          [:participation, :for_querying_participation_records]
                        )
  @participation_repository Application.compile_env!(
                              :klass_hero,
                              [:participation, :for_storing_participation_records]
                            )

  @type actor_role :: :admin | :provider | :staff

  @type params :: %{
          required(:record_id) => String.t(),
          optional(:actor_role) => actor_role(),
          optional(:reason) => String.t(),
          optional(:status) => ParticipationRecord.status(),
          optional(:check_in_at) => DateTime.t(),
          optional(:check_out_at) => DateTime.t(),
          optional(:check_in_notes) => String.t(),
          optional(:check_out_notes) => String.t()
        }

  @type result :: {:ok, ParticipationRecord.t()} | {:error, atom()}

  @spec execute(params()) :: result()
  def execute(%{record_id: record_id} = params) do
    actor_role = Map.get(params, :actor_role, :admin)

    with :ok <- validate_reason(actor_role, params),
         {:ok, record} <- @participation_reader.get_by_id(record_id),
         correction_attrs = build_correction_attrs(actor_role, record, params),
         {:ok, corrected} <- ParticipationRecord.admin_correct(record, correction_attrs) do
      @participation_repository.update(corrected)
    end
  end

  defp validate_reason(:admin, %{reason: reason}) when is_binary(reason) do
    if String.trim(reason) == "", do: {:error, :reason_required}, else: :ok
  end

  defp validate_reason(:admin, _params), do: {:error, :reason_required}
  defp validate_reason(_role, _params), do: :ok

  defp build_correction_attrs(:admin, record, params) do
    params
    |> base_correction_attrs()
    |> apply_admin_reason_notes(record, params)
  end

  defp build_correction_attrs(role, _record, params) when role in [:provider, :staff] do
    notes =
      params
      |> Map.take([:check_in_notes, :check_out_notes])
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    Map.merge(base_correction_attrs(params), notes)
  end

  defp base_correction_attrs(params) do
    params
    |> Map.take([:status, :check_in_at, :check_out_at])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  # Admin-only: append the supplied reason to the field whose change motivated it.
  # Time correction → check-in/out notes alongside the corrected time.
  # Status correction → check-in notes (status changes always start there).
  defp apply_admin_reason_notes(attrs, record, %{reason: reason}) when is_binary(reason) do
    trimmed = String.trim(reason)

    cond do
      Map.has_key?(attrs, :check_in_at) and attrs.check_in_at != record.check_in_at ->
        Map.put(attrs, :check_in_notes, append_admin_note(record.check_in_notes, trimmed))

      Map.has_key?(attrs, :check_out_at) and attrs.check_out_at != record.check_out_at ->
        Map.put(attrs, :check_out_notes, append_admin_note(record.check_out_notes, trimmed))

      Map.has_key?(attrs, :status) and attrs.status != record.status ->
        Map.put(attrs, :check_in_notes, append_admin_note(record.check_in_notes, trimmed))

      true ->
        attrs
    end
  end

  defp apply_admin_reason_notes(attrs, _record, _params), do: attrs

  defp append_admin_note(existing, reason) do
    note = "[Admin correction] #{reason}"

    case existing do
      nil -> note
      "" -> note
      existing -> "#{existing} | #{note}"
    end
  end
end
