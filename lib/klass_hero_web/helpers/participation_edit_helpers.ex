defmodule KlassHeroWeb.Helpers.ParticipationEditHelpers do
  @moduledoc """
  Shared helpers for the inline "edit participation record" form used by the
  provider and staff roster LiveViews.

  Translates form values (notes + optional `datetime-local` departure time)
  into the attrs for `KlassHero.Participation.correct_attendance/3`. It carries
  no actor role: the context derives that from the caller's scope, since a role
  the caller declares is a claim rather than a fact (#1353).
  """

  import Phoenix.Component, only: [assign: 3, to_form: 2]

  alias KlassHero.Participation.ParticipationRecord
  alias Phoenix.LiveView.Socket

  @doc """
  Pre-fill text for the edit form's notes textarea.

  Falls back to whichever notes field the edit will write to:
  `check_out_notes` once the child has departed, otherwise `check_in_notes`.
  """
  @spec default_edit_notes(ParticipationRecord.t() | map()) :: String.t()
  def default_edit_notes(%{check_out_at: %DateTime{}, check_out_notes: notes}) when is_binary(notes), do: notes

  # Departed but no check-out note yet — start the textarea empty so we don't
  # silently copy `check_in_notes` into `check_out_notes` on save.
  def default_edit_notes(%{check_out_at: %DateTime{}}), do: ""

  def default_edit_notes(%{check_in_notes: notes}) when is_binary(notes), do: notes
  def default_edit_notes(_), do: ""

  @doc """
  Build a `correct_attendance` command from raw edit-form params.

  - If a departure time is supplied AND the child has not yet departed,
    a retroactive check-out is recorded (status flip + check_out_at + notes).
  - If the child has already departed, notes go into `check_out_notes`.
  - Otherwise notes go into `check_in_notes`.
  """
  @spec build_edit_correction(ParticipationRecord.t() | map(), map()) ::
          {:ok, map()} | {:error, :invalid_datetime}
  def build_edit_correction(record, params) do
    notes = params |> Map.get("notes", "") |> to_string()
    check_out_at_input = params |> Map.get("check_out_at", "") |> to_string() |> String.trim()

    cond do
      check_out_at_input != "" and is_nil(record.check_out_at) ->
        with {:ok, dt} <- parse_datetime_local(check_out_at_input) do
          {:ok, %{status: :checked_out, check_out_at: dt, check_out_notes: notes}}
        end

      not is_nil(record.check_out_at) ->
        {:ok, %{check_out_notes: notes}}

      true ->
        {:ok, %{check_in_notes: notes}}
    end
  end

  # datetime-local inputs submit "YYYY-MM-DDTHH:MM" (no seconds, no zone)
  @spec parse_datetime_local(String.t()) :: {:ok, DateTime.t()} | {:error, :invalid_datetime}
  defp parse_datetime_local(input) do
    normalized = if byte_size(input) == 16, do: input <> ":00", else: input

    case NaiveDateTime.from_iso8601(normalized) do
      {:ok, ndt} -> {:ok, DateTime.from_naive!(ndt, "Etc/UTC")}
      _ -> {:error, :invalid_datetime}
    end
  end

  @doc """
  Opens an inline form for record `id`: tracks it under `expanded_key` and stores
  a fresh `to_form/2` (named `form_name`, seeded with `field => initial_value`)
  in the `forms_key` map.
  """
  @spec expand_form(Socket.t(), term(), atom(), atom(), term(), atom(), atom()) :: Socket.t()
  def expand_form(socket, id, form_name, field, initial_value, expanded_key, forms_key) do
    form = to_form(%{field => initial_value}, as: form_name)

    socket
    |> assign(expanded_key, id)
    |> assign(forms_key, Map.put(Map.get(socket.assigns, forms_key), id, form))
  end

  @doc "Closes the inline form for record `id`, clearing `expanded_key` and its `forms_key` entry."
  @spec cancel_form(Socket.t(), term(), atom(), atom()) :: Socket.t()
  def cancel_form(socket, id, expanded_key, forms_key) do
    socket
    |> assign(expanded_key, nil)
    |> assign(forms_key, Map.delete(Map.get(socket.assigns, forms_key), id))
  end

  @doc "Replaces the `forms_key` entry for record `id` with a fresh form holding `field => value`."
  @spec update_form(Socket.t(), term(), term(), atom(), atom(), atom()) :: Socket.t()
  def update_form(socket, id, value, form_name, field, forms_key) do
    updated_form = to_form(%{field => value}, as: form_name)
    assign(socket, forms_key, Map.put(Map.get(socket.assigns, forms_key), id, updated_form))
  end

  @doc "Finds a participation record in `socket.assigns.participation_records` by string id."
  @spec find_participation_record(Socket.t(), String.t()) :: ParticipationRecord.t() | nil
  def find_participation_record(socket, record_id) do
    Enum.find(socket.assigns.participation_records, fn record ->
      to_string(record.id) == record_id
    end)
  end
end
