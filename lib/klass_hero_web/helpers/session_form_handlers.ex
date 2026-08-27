defmodule KlassHeroWeb.Helpers.SessionFormHandlers do
  @moduledoc """
  The create-session form's non-visual half, shared by every surface that offers it.

  Until #1074 this lived inside `SessionsLive` — its form markup, its param
  coercion, and its ownership check all local to the one LiveView that rendered
  it. Program Inventory's Sessions popup then needed the same form, and #1501
  deletes `SessionsLive` outright, so copying it would have meant maintaining two
  and losing the original.

  The split is deliberate: this module *decides*, the caller *navigates*. Every
  function returns a value rather than a socket, because the two surfaces differ
  in exactly one respect — where they go afterwards — and threading a
  `push_patch` target through here would put that difference in the shared code.

  Failures are atoms, never sentences, all the way out: coercion and the context
  both refuse in the same currency, so a caller can ask `user_correctable?/1`
  before deciding whether to log. Rendering them is `humanize_error/1`'s job and
  happens once, which is what keeps the two surfaces saying the same thing about
  the same refusal.

  Authorization is **not** here. `KlassHero.Participation.create_session/2` asks
  `SessionAuthorization` itself, which is the whole point of moving it out of the
  web layer; a guard restated in a form helper would be the same mistake one
  level down.
  """

  use Gettext, backend: KlassHeroWeb.Gettext

  alias KlassHero.Accounts.Scope
  alias KlassHero.Participation

  @type form_data :: %{String.t() => String.t()}
  @type refusal ::
          :date_required
          | :invalid_date
          | :time_required
          | :invalid_time
          | :invalid_time_range
          | :duplicate_session
          | :unauthorized

  # Everything a provider can fix by editing the form in front of them. Anything
  # else is ours, and gets logged rather than shown raw.
  @correctable [
    :date_required,
    :invalid_date,
    :time_required,
    :invalid_time,
    :invalid_time_range,
    :duplicate_session,
    :unauthorized
  ]

  @doc """
  Blank form params for a new session.

  `program_id` is pre-set when the surface already knows the program — the
  Sessions popup opens from one program's row, so re-asking would be a step that
  answers a question the user has already answered.
  """
  @spec blank_form(Date.t(), String.t()) :: form_data()
  def blank_form(%Date{} = date, program_id \\ "") do
    %{
      "program_id" => program_id,
      "session_date" => Date.to_iso8601(date),
      "start_time" => "",
      "end_time" => "",
      "location" => "",
      "notes" => "",
      "max_capacity" => ""
    }
  end

  @doc """
  Fills time and location from the chosen program's defaults, leaving anything the
  provider has already typed alone.
  """
  @spec prefill_from_program(form_data(), [struct()]) :: form_data()
  def prefill_from_program(params, programs) do
    case Enum.find(programs, &(&1.id == params["program_id"])) do
      nil ->
        params

      program ->
        params
        |> maybe_set_default("start_time", format_time(program.meeting_start_time))
        |> maybe_set_default("end_time", format_time(program.meeting_end_time))
        |> maybe_set_default("location", program.location || "")
    end
  end

  @doc "Coerces the form's strings and creates the session on behalf of `scope`."
  @spec submit(Scope.t(), form_data()) :: {:ok, Participation.ProgramSession.t()} | {:error, refusal() | atom()}
  def submit(%Scope{} = scope, params) do
    with {:ok, coerced} <- coerce_params(params) do
      Participation.create_session(scope, coerced)
    end
  end

  @doc "Whether a refusal is the provider's to correct, or ours to log."
  @spec user_correctable?(atom()) :: boolean()
  def user_correctable?(reason), do: reason in @correctable

  @doc "The one place a refusal becomes a sentence."
  @spec humanize_error(atom()) :: String.t()
  def humanize_error(:date_required), do: gettext("Date is required")
  def humanize_error(:invalid_date), do: gettext("Invalid date format")
  def humanize_error(:time_required), do: gettext("Time is required")
  def humanize_error(:invalid_time), do: gettext("Invalid time format")
  def humanize_error(:invalid_time_range), do: gettext("End time must be after start time")
  def humanize_error(:duplicate_session), do: gettext("A session already exists at this time")
  def humanize_error(:unauthorized), do: gettext("Unauthorized")
  def humanize_error(:missing_required_fields), do: gettext("Please fill in all required fields")
  def humanize_error(reason), do: gettext("Failed to create session: %{reason}", reason: inspect(reason))

  defp coerce_params(params) do
    with {:ok, date} <- parse_date(params["session_date"]),
         {:ok, start_time} <- parse_time(params["start_time"]),
         {:ok, end_time} <- parse_time(params["end_time"]) do
      attrs = %{
        program_id: params["program_id"],
        session_date: date,
        start_time: start_time,
        end_time: end_time
      }

      {:ok,
       attrs
       |> put_present(:location, params["location"])
       |> put_present(:notes, params["notes"])
       |> put_capacity(params["max_capacity"])}
    end
  end

  defp put_present(attrs, _key, value) when value in [nil, ""], do: attrs
  defp put_present(attrs, key, value), do: Map.put(attrs, key, value)

  defp put_capacity(attrs, raw) do
    case Integer.parse(raw || "") do
      {value, ""} when value > 0 -> Map.put(attrs, :max_capacity, value)
      _other -> attrs
    end
  end

  defp maybe_set_default(params, key, default) do
    if params[key] in [nil, ""], do: Map.put(params, key, default), else: params
  end

  defp format_time(nil), do: ""
  defp format_time(%Time{} = time), do: Calendar.strftime(time, "%H:%M")

  defp parse_date(value) when value in [nil, ""], do: {:error, :date_required}

  defp parse_date(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, _date} = ok -> ok
      {:error, _reason} -> {:error, :invalid_date}
    end
  end

  defp parse_time(value) when value in [nil, ""], do: {:error, :time_required}

  defp parse_time(time_string) do
    # HTML time inputs produce "HH:MM"; Time.from_iso8601/1 requires "HH:MM:SS".
    normalized = if byte_size(time_string) == 5, do: time_string <> ":00", else: time_string

    case Time.from_iso8601(normalized) do
      {:ok, _time} = ok -> ok
      {:error, _reason} -> {:error, :invalid_time}
    end
  end
end
