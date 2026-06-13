defmodule KlassHero.ProgramCatalog.Adapters.Driven.Persistence.Mappers.ProgramMapper do
  @moduledoc """
  Maps between domain Program entities and ProgramSchema Ecto structs.

  This adapter provides bidirectional conversion:
  - to_domain/1: ProgramSchema → Program (for reading from database)
  - to_schema/1: Program → map (for update operations)
  """

  alias KlassHero.ProgramCatalog.Adapters.Driven.Persistence.Schemas.ProgramSchema
  alias KlassHero.ProgramCatalog.Domain.Models.Instructor
  alias KlassHero.ProgramCatalog.Domain.Models.Program
  alias KlassHero.ProgramCatalog.Domain.Models.RegistrationPeriod

  require Logger

  @doc "Converts an Ecto ProgramSchema to a domain Program entity. ID is stringified for domain independence."
  @spec to_domain(ProgramSchema.t()) :: Program.t()
  def to_domain(%ProgramSchema{} = schema) do
    %Program{
      id: to_string(schema.id),
      provider_id: schema.provider_id && to_string(schema.provider_id),
      title: schema.title,
      description: schema.description,
      category: schema.category,
      meeting_days: schema.meeting_days || [],
      meeting_start_time: schema.meeting_start_time,
      meeting_end_time: schema.meeting_end_time,
      start_date: schema.start_date,
      age_range: schema.age_range,
      price: schema.price,
      pricing_period: schema.pricing_period,
      end_date: schema.end_date,
      lock_version: schema.lock_version,
      location: schema.location,
      cover_image_url: schema.cover_image_url,
      origin: origin_to_atom(schema.origin),
      instructor: build_instructor(schema),
      registration_period: build_registration_period(schema),
      inserted_at: schema.inserted_at,
      updated_at: schema.updated_at
    }
  end

  @doc "Converts a domain Program entity to update attrs. Excludes id, timestamps, and lock_version."
  def to_schema(%Program{} = program) do
    base = %{
      title: program.title,
      description: program.description,
      category: program.category,
      meeting_days: program.meeting_days,
      meeting_start_time: program.meeting_start_time,
      meeting_end_time: program.meeting_end_time,
      start_date: program.start_date,
      age_range: program.age_range,
      price: program.price,
      pricing_period: program.pricing_period,
      end_date: program.end_date,
      location: program.location,
      cover_image_url: program.cover_image_url,
      origin: program.origin && to_string(program.origin),
      provider_id: program.provider_id,
      registration_start_date: program.registration_period && program.registration_period.start_date,
      registration_end_date: program.registration_period && program.registration_period.end_date
    }

    add_instructor_fields(base, program.instructor)
  end

  # RegistrationPeriod is a value object assembled from flat schema columns; dates may be nil.
  defp build_registration_period(%ProgramSchema{} = schema) do
    %RegistrationPeriod{
      start_date: schema.registration_start_date,
      end_date: schema.registration_end_date
    }
  end

  # Instructor is optional — guard against building a VO from nil data.
  defp build_instructor(%ProgramSchema{instructor_id: nil}), do: nil

  defp build_instructor(%ProgramSchema{} = schema) do
    case Instructor.from_persistence(%{
           id: to_string(schema.instructor_id),
           name: schema.instructor_name,
           headshot_url: schema.instructor_headshot_url
         }) do
      {:ok, instructor} ->
        instructor

      {:error, reason} ->
        Logger.error("[ProgramMapper] Instructor data invalid, skipping",
          instructor_id: to_string(schema.instructor_id),
          instructor_name: schema.instructor_name,
          reason: inspect(reason)
        )

        nil
    end
  end

  defp add_instructor_fields(attrs, nil) do
    Map.merge(attrs, %{instructor_id: nil, instructor_name: nil, instructor_headshot_url: nil})
  end

  defp add_instructor_fields(attrs, %Instructor{} = instructor) do
    Map.merge(attrs, %{
      instructor_id: instructor.id,
      instructor_name: instructor.name,
      instructor_headshot_url: instructor.headshot_url
    })
  end

  defp origin_to_atom("self_posted"), do: :self_posted
  defp origin_to_atom("business_assigned"), do: :business_assigned
  defp origin_to_atom(nil), do: :self_posted

  defp origin_to_atom(unknown) do
    Logger.warning("[ProgramMapper] Unknown origin value, defaulting to :self_posted",
      reason: inspect(unknown)
    )

    :self_posted
  end
end
