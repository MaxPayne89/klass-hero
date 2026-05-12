defmodule KlassHero.ProgramCatalog.Adapters.Driven.Persistence.Schemas.ProgramSchema do
  @moduledoc """
  Ecto schema for the programs table.

  This is an infrastructure adapter that maps database records to Ecto structs.
  Use ProgramMapper to convert between ProgramSchema and domain Program entities.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.ProgramCatalog.Domain.Services.ProgramCategories

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "programs" do
    field :title, :string
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
    field :origin, :string, default: "self_posted"
    field :instructor_id, :binary_id
    field :instructor_name, :string
    field :instructor_headshot_url, :string
    # Free-text label for academic season grouping (e.g. "School Name 24/25: Semester 2")
    field :season, :string

    timestamps()
  end

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          title: String.t() | nil,
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
          origin: String.t() | nil,
          instructor_id: Ecto.UUID.t() | nil,
          instructor_name: String.t() | nil,
          instructor_headshot_url: String.t() | nil,
          season: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc """
  Creates a changeset for validation.

  Required fields:
  - title (1-100 characters)
  - description (1-500 characters)
  - category (valid program category)
  - age_range (non-empty)
  - price (>= 0)
  - pricing_period (non-empty)

  Optional scheduling fields:
  - meeting_days (list of valid weekday names)
  - meeting_start_time / meeting_end_time (must be set together, end > start)
  - start_date (must be before end_date when both present)
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(program_schema, attrs) do
    program_schema
    |> cast(attrs, [
      :title,
      :description,
      :category,
      :age_range,
      :price,
      :pricing_period,
      :end_date,
      :provider_id,
      :location,
      :cover_image_url,
      :instructor_id,
      :instructor_name,
      :instructor_headshot_url,
      :meeting_days,
      :meeting_start_time,
      :meeting_end_time,
      :start_date,
      :registration_start_date,
      :registration_end_date,
      :season
    ])
    |> validate_required([
      :title,
      :description,
      :category,
      :age_range,
      :price,
      :pricing_period
    ])
    |> validate_length(:title, min: 1, max: 100)
    |> validate_length(:description, min: 1, max: 500)
    |> validate_length(:age_range, min: 1, max: 100)
    |> validate_length(:pricing_period, min: 1, max: 100)
    |> validate_length(:season, max: 255)
    |> validate_inclusion(:category, ProgramCategories.program_categories())
    |> validate_number(:price, greater_than_or_equal_to: 0)
    |> validate_meeting_days()
    |> validate_time_pairing()
    |> validate_date_range()
    |> validate_registration_date_range()
  end

  @doc """
  Creates a changeset for program creation.

  Requires only the minimal fields needed to create a program.
  Schedule, age_range, and pricing_period are optional at creation time.
  """
  def create_changeset(program_schema, attrs) do
    program_schema
    |> cast(attrs, [
      :title,
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
      :season
    ])
    # Trigger: provider_id, instructor fields arrive from trusted server-side code
    # Why: including them in cast would allow form param injection
    # Outcome: fields are set explicitly via put_change, not from user input
    |> maybe_put_change(:provider_id, attrs)
    |> maybe_put_change(:cover_image_url, attrs)
    |> maybe_put_change(:instructor_id, attrs)
    |> maybe_put_change(:instructor_name, attrs)
    |> maybe_put_change(:instructor_headshot_url, attrs)
    |> maybe_put_change(:origin, attrs)
    |> validate_required([:title, :description, :category, :price, :provider_id])
    |> validate_inclusion(:origin, ["self_posted", "business_assigned"])
    |> validate_length(:title, min: 1, max: 100)
    |> validate_length(:description, min: 1, max: 500)
    |> validate_length(:location, max: 255)
    |> validate_length(:cover_image_url, max: 500)
    |> validate_length(:instructor_name, max: 200)
    |> validate_length(:season, max: 255)
    |> validate_inclusion(:category, ProgramCategories.program_categories())
    |> validate_number(:price, greater_than_or_equal_to: 0)
    |> validate_meeting_days()
    |> validate_time_pairing()
    |> validate_date_range()
    |> validate_registration_date_range()
    |> foreign_key_constraint(:provider_id)
    |> foreign_key_constraint(:instructor_id)
  end

  @doc """
  Creates an update changeset with optimistic locking.

  Applies the same validations as changeset/2 but adds optimistic locking
  to prevent concurrent update conflicts.

  Returns a changeset that will fail with Ecto.StaleEntryError if the
  record has been modified by another process since it was loaded.
  """
  def update_changeset(program_schema, attrs) do
    program_schema
    |> cast(attrs, [
      :title,
      :description,
      :category,
      :age_range,
      :price,
      :pricing_period,
      :end_date,
      :location,
      :cover_image_url,
      :instructor_id,
      :instructor_name,
      :instructor_headshot_url,
      :meeting_days,
      :meeting_start_time,
      :meeting_end_time,
      :start_date,
      :registration_start_date,
      :registration_end_date,
      :season
    ])
    |> validate_required([
      :title,
      :description,
      :category,
      :price
    ])
    |> validate_length(:title, min: 1, max: 100)
    |> validate_length(:description, min: 1, max: 500)
    |> validate_length(:age_range, max: 100)
    |> validate_length(:pricing_period, max: 100)
    |> validate_length(:season, max: 255)
    |> validate_inclusion(:category, ProgramCategories.program_categories())
    |> validate_number(:price, greater_than_or_equal_to: 0)
    |> validate_meeting_days()
    |> validate_time_pairing()
    |> validate_date_range()
    |> validate_registration_date_range()
    |> optimistic_lock(:lock_version)
  end

  @valid_weekdays ~w(Monday Tuesday Wednesday Thursday Friday Saturday Sunday)

  # Trigger: meeting_days contains values not in the valid weekday list
  # Why: prevent typos or invalid day names from corrupting schedule data
  # Outcome: changeset error listing the invalid day names
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

  # Trigger: only one of start_time/end_time is set, or end_time <= start_time
  # Why: a half-specified time range is ambiguous; end must follow start chronologically
  # Outcome: changeset error on the appropriate time field
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

  # Trigger: start_date is strictly after end_date
  # Why: a program's start must be on or before its end (single-day programs allowed)
  # Outcome: changeset error on start_date
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

  # Trigger: registration_start_date is on or after registration_end_date
  # Why: registration window must have start before end for a valid period
  # Outcome: changeset error on registration_start_date
  defp validate_registration_date_range(changeset) do
    start_date = get_field(changeset, :registration_start_date)
    end_date = get_field(changeset, :registration_end_date)

    if is_nil(start_date) or is_nil(end_date) do
      changeset
    else
      if Date.before?(start_date, end_date) do
        changeset
      else
        add_error(changeset, :registration_start_date, "must be before registration end date")
      end
    end
  end

  # Trigger: attrs may or may not contain the given key
  # Why: programmatic fields must bypass cast but still appear as changes
  # Outcome: put_change only when the key is present in the atom-keyed attrs map
  defp maybe_put_change(changeset, key, attrs) when is_atom(key) do
    if Map.has_key?(attrs, key) do
      put_change(changeset, key, Map.get(attrs, key))
    else
      changeset
    end
  end
end
