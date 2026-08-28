defmodule KlassHero.ProgramCatalog.Program do
  @moduledoc """
  A program (afterschool activity, camp, or class trip) in the Program Catalog.

  Conventional Phoenix model: the Ecto schema *is* the domain struct. Validation
  lives in the changesets (the single gatekeeper); pure, side-effect-free helpers
  make up the functional core. All persistence happens in `KlassHero.ProgramCatalog`.

  The registration window is denormalized into flat columns (`registration_*`) and
  exposed as the nested `registration_period` value object (`%RegistrationPeriod{}`),
  populated by `load_value_objects/1` after a read. The lead instructor is NOT held
  here — it is the single source of truth on `program_staff_assignments`
  (`is_lead_instructor`), read via the `Provider` facade (see ADR 0016).
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  alias KlassHero.ProgramCatalog.Domain.Services.ProgramCategories
  alias KlassHero.ProgramCatalog.Domain.Services.ProgramPricing
  alias KlassHero.ProgramCatalog.RegistrationPeriod

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "programs" do
    field :title, :string
    field :subtitle, :string
    field :description, :string
    field :category, :string
    field :meeting_days, {:array, :string}, default: []
    field :meeting_start_time, :time
    field :meeting_end_time, :time
    field :start_date, :date
    field :age_range, :string
    field :price, :decimal
    field :pricing_period, :string
    field :lock_version, :integer, default: 1
    field :end_date, :date
    field :registration_start_date, :date
    field :registration_end_date, :date
    field :provider_id, :binary_id
    field :location, :string
    field :cover_image_url, :string

    # Inherited by schedule-generated Sessions as their Session Capacity.
    # Not the enrollment cap — that is `enrollment_policies.max_enrollment`,
    # owned by Enrollment and enforced when a place is booked.
    field :default_session_capacity, :integer
    field :origin, Ecto.Enum, values: [:self_posted, :business_assigned], default: :self_posted
    # Free-text label for academic season grouping (e.g. "School Name 24/25: Semester 2").
    field :season, :string

    # Nested value object assembled from the flat columns above by
    # load_value_objects/1; never persisted directly.
    field :registration_period, :any, virtual: true

    timestamps()
  end

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          title: String.t() | nil,
          subtitle: String.t() | nil,
          description: String.t() | nil,
          category: String.t() | nil,
          meeting_days: [String.t()],
          meeting_start_time: Time.t() | nil,
          meeting_end_time: Time.t() | nil,
          start_date: Date.t() | nil,
          age_range: String.t() | nil,
          price: Decimal.t() | nil,
          pricing_period: String.t() | nil,
          lock_version: integer() | nil,
          end_date: Date.t() | nil,
          registration_start_date: Date.t() | nil,
          registration_end_date: Date.t() | nil,
          provider_id: Ecto.UUID.t() | nil,
          location: String.t() | nil,
          cover_image_url: String.t() | nil,
          default_session_capacity: integer() | nil,
          origin: :self_posted | :business_assigned | nil,
          season: String.t() | nil,
          registration_period: RegistrationPeriod.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc """
  Changeset for creating a program. Schedule, age_range, and pricing_period are
  optional; provider/origin fields are set server-side (bypassing `cast`) to
  prevent form-param injection.
  """
  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(program, attrs) do
    program
    |> cast(attrs, [
      :title,
      :subtitle,
      :description,
      :category,
      :price,
      :location,
      :meeting_days,
      :meeting_start_time,
      :meeting_end_time,
      :start_date,
      :end_date,
      :registration_start_date,
      :registration_end_date,
      :season,
      :default_session_capacity
    ])
    |> maybe_put_change(:provider_id, attrs)
    |> maybe_put_change(:cover_image_url, attrs)
    |> maybe_put_change(:origin, attrs)
    |> validate_required([:title, :description, :category, :price, :provider_id])
    |> validate_length(:title, min: 1, max: 100)
    |> validate_length(:subtitle, max: 150)
    |> validate_length(:description, min: 1, max: 500)
    |> validate_length(:location, max: 255)
    |> validate_length(:cover_image_url, max: 500)
    |> validate_length(:season, max: 255)
    |> validate_inclusion(:category, ProgramCategories.program_categories())
    |> validate_number(:price, greater_than_or_equal_to: 0)
    |> validate_number(:default_session_capacity, greater_than: 0)
    |> validate_meeting_days()
    |> validate_time_pairing()
    |> validate_date_range()
    |> validate_registration_date_range()
    |> foreign_key_constraint(:provider_id)
  end

  @doc """
  Changeset for updating a program, with optimistic locking. Raises
  `Ecto.StaleEntryError` on concurrent modification.
  """
  @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
  def update_changeset(program, attrs) do
    program
    |> cast(attrs, [
      :title,
      :subtitle,
      :description,
      :category,
      :age_range,
      :price,
      :pricing_period,
      :end_date,
      :location,
      :cover_image_url,
      :meeting_days,
      :meeting_start_time,
      :meeting_end_time,
      :start_date,
      :registration_start_date,
      :registration_end_date,
      :season,
      :default_session_capacity
    ])
    |> validate_required([:title, :description, :category, :price])
    |> validate_length(:title, min: 1, max: 100)
    |> validate_length(:subtitle, max: 150)
    |> validate_length(:description, min: 1, max: 500)
    |> validate_length(:age_range, max: 100)
    |> validate_length(:pricing_period, max: 100)
    |> validate_length(:season, max: 255)
    |> validate_inclusion(:category, ProgramCategories.program_categories())
    |> validate_number(:price, greater_than_or_equal_to: 0)
    |> validate_number(:default_session_capacity, greater_than: 0)
    |> validate_meeting_days()
    |> validate_time_pairing()
    |> validate_date_range()
    |> validate_registration_date_range()
    |> optimistic_lock(:lock_version)
  end

  @doc """
  Narrows a query to programs owned by `provider_id`.

  Composing this scope makes a foreign row *unreachable* rather than fetched and
  then rejected, so a caller's `nil` branch already collapses foreign to missing.
  """
  @spec owned_by(Ecto.Queryable.t(), String.t()) :: Ecto.Query.t()
  def owned_by(query \\ __MODULE__, provider_id) when is_binary(provider_id) do
    from p in query, where: p.provider_id == ^provider_id
  end

  @doc """
  Populates the nested `registration_period` value object from the flat columns of
  a freshly-loaded program. Pure — call after every read.
  """
  @spec load_value_objects(t()) :: t()
  def load_value_objects(%__MODULE__{} = program) do
    %{program | registration_period: build_registration_period(program)}
  end

  @doc """
  Whether the program is free — priced, at zero.

  A program with no price yet is *not* free, it is unpriced; `price_state/1`
  keeps the two apart and this predicate collapses them on purpose, for callers
  that only care whether money changes hands.
  """
  @spec free?(t()) :: boolean()
  def free?(%__MODULE__{price: price}), do: ProgramPricing.price_state(price) == :free

  @doc """
  Whether the program has closed to its staff — ended on or before `cutoff`.

  `cutoff` is today minus the grace window, computed by the caller
  (`KlassHero.ProgramCatalog.closed?/1`) so this stays pure and the window stays
  configurable. An open-ended program (`end_date: nil`) never closes.

  Gates **staff** only: the provider owns the data and corrects rosters after a
  season ends, and an admin correction is a separate path (ADR-0017).
  """
  @spec closed?(t(), Date.t()) :: boolean()
  def closed?(%__MODULE__{end_date: nil}, _cutoff), do: false
  def closed?(%__MODULE__{end_date: end_date}, cutoff), do: Date.before?(end_date, cutoff)

  @doc "Whether registration is currently open. Requires `load_value_objects/1` first."
  @spec registration_open?(t()) :: boolean()
  def registration_open?(%__MODULE__{registration_period: %RegistrationPeriod{} = rp}) do
    RegistrationPeriod.open?(rp)
  end

  @doc "The current registration status. Requires `load_value_objects/1` first."
  @spec registration_status(t()) :: RegistrationPeriod.status()
  def registration_status(%__MODULE__{registration_period: %RegistrationPeriod{} = rp}) do
    RegistrationPeriod.status(rp)
  end

  # RegistrationPeriod is always present (nil dates → :always_open).
  defp build_registration_period(%__MODULE__{} = program) do
    %RegistrationPeriod{
      start_date: program.registration_start_date,
      end_date: program.registration_end_date
    }
  end

  @valid_weekdays ~w(Monday Tuesday Wednesday Thursday Friday Saturday Sunday)

  # Derived from @valid_weekdays so the weekday vocabulary has one definition:
  # `Date.day_of_week/1` numbers Monday 1 through Sunday 7.
  @weekday_numbers @valid_weekdays |> Enum.with_index(1) |> Map.new()

  # A term of twice-weekly sessions is ~40; the cap only rejects schedules no
  # provider plausibly means, rather than letting one expand to tens of thousands
  # of rows in a single insert.
  @max_meeting_dates 500

  @doc """
  Expands the advertised recurring schedule into the concrete dates it falls on,
  in ascending order.

  Pure. The weekday vocabulary stays here beside `validate_meeting_days/1`, so
  consumers receive `Date` structs and never handle day-name strings themselves.

  Requires the whole schedule — meeting days plus both times plus both dates.
  A partial schedule is `{:error, :incomplete_schedule}` rather than an empty
  list, so a caller can tell "this program has no schedule" apart from "this
  schedule genuinely has no matching dates".
  """
  @spec meeting_dates(t()) :: {:ok, [Date.t()]} | {:error, :incomplete_schedule | :schedule_range_too_large}
  def meeting_dates(%__MODULE__{} = program) do
    with {:ok, weekdays} <- scheduled_weekdays(program) do
      dates =
        program.start_date
        |> Date.range(program.end_date)
        |> Stream.filter(&(Date.day_of_week(&1) in weekdays))
        |> Enum.take(@max_meeting_dates + 1)

      if length(dates) > @max_meeting_dates do
        {:error, :schedule_range_too_large}
      else
        {:ok, dates}
      end
    end
  end

  defp scheduled_weekdays(%__MODULE__{
         meeting_days: [_ | _] = days,
         meeting_start_time: %Time{},
         meeting_end_time: %Time{},
         start_date: %Date{} = start_date,
         end_date: %Date{} = end_date
       }) do
    # Unrecognised names are dropped rather than raising: the changeset already
    # rejects them, so reaching here means data that predates that validation.
    weekdays = for day <- days, number = Map.get(@weekday_numbers, day), into: MapSet.new(), do: number

    if Enum.empty?(weekdays) or Date.after?(start_date, end_date) do
      {:error, :incomplete_schedule}
    else
      {:ok, weekdays}
    end
  end

  defp scheduled_weekdays(%__MODULE__{}), do: {:error, :incomplete_schedule}

  defp validate_meeting_days(changeset) do
    validate_change(changeset, :meeting_days, fn :meeting_days, days ->
      invalid = Enum.reject(days, &(&1 in @valid_weekdays))

      if invalid == [] do
        []
      else
        [{:meeting_days, "contains invalid days: #{Enum.join(invalid, ", ")}"}]
      end
    end)
  end

  defp validate_time_pairing(changeset) do
    start_time = get_field(changeset, :meeting_start_time)
    end_time = get_field(changeset, :meeting_end_time)

    cond do
      is_nil(start_time) and is_nil(end_time) ->
        changeset

      is_nil(start_time) or is_nil(end_time) ->
        add_error(changeset, :meeting_start_time, "both start and end times must be set together")

      Time.compare(end_time, start_time) != :gt ->
        add_error(changeset, :meeting_end_time, "must be after start time")

      true ->
        changeset
    end
  end

  defp validate_date_range(changeset) do
    start_date = get_field(changeset, :start_date)
    end_date = get_field(changeset, :end_date)

    cond do
      is_nil(start_date) or is_nil(end_date) ->
        changeset

      Date.after?(start_date, end_date) ->
        add_error(changeset, :start_date, "must be on or before end date")

      true ->
        changeset
    end
  end

  defp validate_registration_date_range(changeset) do
    start_date = get_field(changeset, :registration_start_date)
    end_date = get_field(changeset, :registration_end_date)

    cond do
      is_nil(start_date) or is_nil(end_date) -> changeset
      Date.before?(start_date, end_date) -> changeset
      true -> add_error(changeset, :registration_start_date, "must be before registration end date")
    end
  end

  # Programmatic fields bypass cast; put_change only when present so absent keys
  # don't overwrite existing values.
  defp maybe_put_change(changeset, key, attrs) when is_atom(key) do
    cond do
      Map.has_key?(attrs, key) -> put_change(changeset, key, Map.get(attrs, key))
      Map.has_key?(attrs, to_string(key)) -> put_change(changeset, key, Map.get(attrs, to_string(key)))
      true -> changeset
    end
  end
end
