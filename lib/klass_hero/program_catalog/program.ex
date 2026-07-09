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
  (`is_lead_instructor`), read via the `Provider` facade (see ADR 0007).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.ProgramCatalog.Domain.Services.ProgramCategories
  alias KlassHero.ProgramCatalog.RegistrationPeriod

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
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
    |> maybe_put_change(:provider_id, attrs)
    |> maybe_put_change(:cover_image_url, attrs)
    |> maybe_put_change(:origin, attrs)
    |> validate_required([:title, :description, :category, :price, :provider_id])
    |> validate_length(:title, min: 1, max: 100)
    |> validate_length(:description, min: 1, max: 500)
    |> validate_length(:location, max: 255)
    |> validate_length(:cover_image_url, max: 500)
    |> validate_length(:season, max: 255)
    |> validate_inclusion(:category, ProgramCategories.program_categories())
    |> validate_number(:price, greater_than_or_equal_to: 0)
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
      :season
    ])
    |> validate_required([:title, :description, :category, :price])
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

  @doc """
  Populates the nested `registration_period` value object from the flat columns of
  a freshly-loaded program. Pure — call after every read.
  """
  @spec load_value_objects(t()) :: t()
  def load_value_objects(%__MODULE__{} = program) do
    %{program | registration_period: build_registration_period(program)}
  end

  @doc "Whether the program is free (price is 0)."
  @spec free?(t()) :: boolean()
  def free?(%__MODULE__{price: price}), do: Decimal.equal?(price, Decimal.new(0))

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
