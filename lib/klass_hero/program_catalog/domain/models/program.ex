defmodule KlassHero.ProgramCatalog.Domain.Models.Program do
  @moduledoc """
  Pure domain entity representing an afterschool program, camp, or class trip.

  This is the aggregate root for the Program Catalog bounded context.
  Contains only business logic and validation rules, no database dependencies.
  """

  alias KlassHero.ProgramCatalog.Domain.Models.Instructor
  alias KlassHero.ProgramCatalog.Domain.Models.RegistrationPeriod
  alias KlassHero.ProgramCatalog.Domain.Services.ProgramCategories

  @enforce_keys [:title, :description, :category, :price]

  defstruct [
    :id,
    :provider_id,
    :title,
    :description,
    :category,
    :age_range,
    :price,
    :pricing_period,
    :end_date,
    :lock_version,
    :location,
    :cover_image_url,
    :origin,
    :instructor,
    :inserted_at,
    :updated_at,
    :meeting_start_time,
    :meeting_end_time,
    :start_date,
    meeting_days: [],
    registration_period: %RegistrationPeriod{}
  ]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          provider_id: String.t(),
          title: String.t(),
          description: String.t(),
          category: String.t(),
          age_range: String.t() | nil,
          price: Decimal.t(),
          pricing_period: String.t() | nil,
          end_date: Date.t() | nil,
          lock_version: non_neg_integer() | nil,
          location: String.t() | nil,
          cover_image_url: String.t() | nil,
          origin: :self_posted | :business_assigned | nil,
          instructor: Instructor.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil,
          meeting_days: [String.t()],
          meeting_start_time: Time.t() | nil,
          meeting_end_time: Time.t() | nil,
          start_date: Date.t() | nil,
          registration_period: RegistrationPeriod.t()
        }

  # Trusted path from persistence; external callers must use create/1 or apply_changes/2.
  @doc false
  @spec new(map()) :: {:ok, t()}
  def new(attrs) when is_map(attrs) do
    {:ok, struct!(__MODULE__, attrs)}
  end

  @doc false
  @spec new!(map()) :: t()
  def new!(attrs) when is_map(attrs) do
    struct!(__MODULE__, attrs)
  end

  @doc """
  Checks runtime business invariants (full validation lives in the Ecto schema).
  """
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{} = program) do
    is_binary(program.title) and String.trim(program.title) != "" and
      is_binary(program.description) and String.trim(program.description) != "" and
      match?(%Decimal{}, program.price) and Decimal.compare(program.price, Decimal.new(0)) != :lt
  end

  @doc """
  Creates a Program from untrusted input, validating all business rules.
  Returns `{:ok, Program.t()}` with `id: nil` — the persistence layer assigns the ID.
  """
  @spec create(map()) :: {:ok, t()} | {:error, [String.t()]}
  def create(attrs) when is_map(attrs) do
    attrs = normalize_keys(attrs)

    with {:ok, instructor} <- build_instructor_from_attrs(attrs),
         {:ok, registration_period} <- build_registration_period(attrs) do
      build_base(attrs, instructor, registration_period)
    end
  end

  @doc """
  Applies changes to an existing Program, re-validating all business invariants.
  Only keys present in `changes` are updated; others are preserved.
  """
  @spec apply_changes(t(), map()) :: {:ok, t()} | {:error, [String.t()]}
  def apply_changes(%__MODULE__{} = program, changes) when is_map(changes) do
    with {:ok, instructor} <- resolve_instructor(program, changes) do
      updated = merge_fields(program, changes, instructor)
      errors = validate_mutation_invariants(updated)

      if errors == [] do
        {:ok, updated}
      else
        {:error, errors}
      end
    end
  end

  @doc "Returns true if the program price is $0."
  @spec free?(t()) :: boolean()
  def free?(%__MODULE__{price: price}), do: Decimal.equal?(price, Decimal.new(0))

  @doc "Returns true if registration is currently open."
  @spec registration_open?(t()) :: boolean()
  def registration_open?(%__MODULE__{registration_period: rp}), do: RegistrationPeriod.open?(rp)

  @doc "Returns the current registration status."
  @spec registration_status(t()) :: RegistrationPeriod.status()
  def registration_status(%__MODULE__{registration_period: rp}), do: RegistrationPeriod.status(rp)

  # String.to_existing_atom/1 prevents atom table exhaustion; unknown string keys
  # correctly raise ArgumentError (unknown field on the struct).
  defp normalize_keys(%{__struct__: _} = attrs), do: Map.from_struct(attrs)

  defp normalize_keys(attrs) do
    Map.new(attrs, fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
      {k, v} when is_atom(k) -> {k, v}
    end)
  end

  defp build_instructor_from_attrs(%{instructor: instructor_attrs}) when is_map(instructor_attrs) do
    case Instructor.new(instructor_attrs) do
      {:ok, instructor} -> {:ok, instructor}
      {:error, reasons} -> {:error, Enum.map(reasons, &"Instructor: #{&1}")}
    end
  end

  defp build_instructor_from_attrs(_), do: {:ok, nil}

  defp build_registration_period(attrs) do
    RegistrationPeriod.new(%{
      start_date: attrs[:registration_start_date],
      end_date: attrs[:registration_end_date]
    })
  end

  defp build_base(attrs, instructor, registration_period) do
    errors = validate_creation_invariants(attrs)

    if errors == [] do
      {:ok,
       %__MODULE__{
         title: attrs[:title],
         description: attrs[:description],
         category: attrs[:category],
         price: attrs[:price],
         provider_id: attrs[:provider_id],
         origin: :self_posted,
         meeting_days: attrs[:meeting_days] || [],
         meeting_start_time: attrs[:meeting_start_time],
         meeting_end_time: attrs[:meeting_end_time],
         start_date: attrs[:start_date],
         age_range: attrs[:age_range],
         pricing_period: attrs[:pricing_period],
         end_date: attrs[:end_date],
         location: attrs[:location],
         cover_image_url: attrs[:cover_image_url],
         instructor: instructor,
         registration_period: registration_period
       }}
    else
      {:error, errors}
    end
  end

  defp validate_creation_invariants(attrs) do
    []
    |> validate_required_string(attrs, :title, "title is required")
    |> validate_required_string(attrs, :description, "description is required")
    |> validate_category(attrs[:category])
    |> validate_price(attrs[:price])
    |> validate_provider_id(attrs[:provider_id])
    |> validate_scheduling(attrs)
  end

  defp validate_required_string(errors, attrs, key, message) do
    value = attrs[key]

    if is_binary(value) and String.trim(value) != "" do
      errors
    else
      [message | errors]
    end
  end

  defp validate_category(errors, category) when is_binary(category) do
    if ProgramCategories.valid_program_category?(category) do
      errors
    else
      ["category is invalid" | errors]
    end
  end

  defp validate_category(errors, _), do: ["category is required" | errors]

  defp validate_price(errors, %Decimal{} = price) do
    if Decimal.compare(price, Decimal.new(0)) == :lt do
      ["price must be greater than or equal to 0" | errors]
    else
      errors
    end
  end

  defp validate_price(errors, _), do: ["price is required" | errors]

  defp validate_provider_id(errors, id) when is_binary(id) and byte_size(id) > 0, do: errors
  defp validate_provider_id(errors, _), do: ["provider ID is required" | errors]

  defp resolve_instructor(_program, %{instructor: nil}), do: {:ok, nil}

  defp resolve_instructor(_program, %{instructor: attrs}) when is_map(attrs) do
    case Instructor.new(attrs) do
      {:ok, instructor} -> {:ok, instructor}
      {:error, reasons} -> {:error, Enum.map(reasons, &"Instructor: #{&1}")}
    end
  end

  defp resolve_instructor(program, _changes), do: {:ok, program.instructor}

  @updatable_fields ~w(title description category price
                       meeting_days meeting_start_time meeting_end_time start_date
                       age_range pricing_period end_date location cover_image_url
                       registration_period)a

  defp merge_fields(program, changes, instructor) do
    merged =
      Enum.reduce(@updatable_fields, program, fn field, acc ->
        if Map.has_key?(changes, field) do
          Map.put(acc, field, Map.get(changes, field))
        else
          acc
        end
      end)

    %{merged | instructor: instructor}
  end

  defp validate_mutation_invariants(program) do
    struct_fields = Map.from_struct(program)

    []
    |> validate_required_string(struct_fields, :title, "title is required")
    |> validate_required_string(struct_fields, :description, "description is required")
    |> validate_category(program.category)
    |> validate_price(program.price)
    |> validate_scheduling(struct_fields)
    |> validate_registration_period_struct(program.registration_period)
  end

  # Re-validates date ordering on mutation path (struct already constructed).
  defp validate_registration_period_struct(errors, %RegistrationPeriod{start_date: nil, end_date: nil}), do: errors

  defp validate_registration_period_struct(errors, %RegistrationPeriod{} = rp) do
    case RegistrationPeriod.new(%{start_date: rp.start_date, end_date: rp.end_date}) do
      {:ok, _} -> errors
      {:error, rp_errors} -> rp_errors ++ errors
    end
  end

  @valid_weekdays ~w(Monday Tuesday Wednesday Thursday Friday Saturday Sunday)

  defp validate_scheduling(errors, attrs) do
    errors
    |> validate_meeting_days(attrs[:meeting_days])
    |> validate_time_pairing(attrs[:meeting_start_time], attrs[:meeting_end_time])
    |> validate_date_range(attrs[:start_date], attrs[:end_date])
  end

  defp validate_meeting_days(errors, nil), do: errors
  defp validate_meeting_days(errors, []), do: errors

  defp validate_meeting_days(errors, days) when is_list(days) do
    if Enum.all?(days, &(&1 in @valid_weekdays)) do
      errors
    else
      ["meeting_days contains invalid weekday names" | errors]
    end
  end

  defp validate_meeting_days(errors, _), do: ["meeting_days must be a list" | errors]

  defp validate_time_pairing(errors, nil, nil), do: errors

  defp validate_time_pairing(errors, %Time{} = start_time, %Time{} = end_time) do
    if Time.after?(end_time, start_time) do
      errors
    else
      ["meeting_end_time must be after meeting_start_time" | errors]
    end
  end

  defp validate_time_pairing(errors, _, _) do
    ["both meeting_start_time and meeting_end_time must be set together" | errors]
  end

  defp validate_date_range(errors, nil, _), do: errors
  defp validate_date_range(errors, _, nil), do: errors

  defp validate_date_range(errors, %Date{} = start_date, %Date{} = end_date) do
    if Date.after?(start_date, end_date) do
      ["start_date must be on or before end_date" | errors]
    else
      errors
    end
  end

  defp validate_date_range(errors, _, _) do
    ["start_date or end_date has an invalid type" | errors]
  end
end
