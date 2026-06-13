defmodule KlassHero.ProgramCatalog.Application.Commands.UpdateProgram do
  @moduledoc """
  Use case for updating an existing program.

  Orchestrates: load aggregate -> apply changes through domain model -> persist.
  Delegates persistence (including optimistic locking) to the repository adapter.
  """

  alias KlassHero.ProgramCatalog.Domain.Events.ProgramEvents
  alias KlassHero.ProgramCatalog.Domain.Models.Program
  alias KlassHero.Shared.DomainEventBus

  require Logger

  @repository Application.compile_env!(:klass_hero, [:program_catalog, :repository])

  def execute(id, changes) when is_binary(id) and is_map(changes) do
    Logger.info("[UpdateProgram] Starting program update", program_id: id)

    with {:ok, program} <- @repository.get_by_id(id),
         {:ok, updated} <- Program.apply_changes(program, changes),
         {:ok, persisted} <- @repository.update(updated) do
      dispatch_update_event(persisted)
      maybe_dispatch_schedule_event(program, persisted)
      Logger.info("[UpdateProgram] Program updated successfully", program_id: id)
      {:ok, persisted}
    else
      {:error, :not_found} = error ->
        Logger.info("[UpdateProgram] Program not found", program_id: id)
        error

      {:error, :stale_data} = error ->
        Logger.warning("[UpdateProgram] Stale data conflict", program_id: id)
        error

      {:error, errors} = error when is_list(errors) ->
        Logger.warning("[UpdateProgram] Domain validation failed",
          program_id: id,
          errors: inspect(errors)
        )

        error

      {:error, _changeset} = error ->
        Logger.warning("[UpdateProgram] Persistence validation failed", program_id: id)
        error
    end
  end

  defp dispatch_update_event(program) do
    instructor_payload = build_instructor_payload(program.instructor)

    payload =
      %{
        provider_id: program.provider_id,
        title: program.title,
        description: program.description,
        category: program.category,
        age_range: program.age_range,
        price: program.price,
        pricing_period: program.pricing_period,
        location: program.location,
        cover_image_url: program.cover_image_url,
        start_date: program.start_date,
        end_date: program.end_date,
        meeting_days: program.meeting_days,
        meeting_start_time: program.meeting_start_time,
        meeting_end_time: program.meeting_end_time,
        registration_start_date: program.registration_period.start_date,
        registration_end_date: program.registration_period.end_date
      }
      |> Map.merge(instructor_payload)

    event = ProgramEvents.program_updated(program.id, payload)

    case DomainEventBus.dispatch(KlassHero.ProgramCatalog, event) do
      :ok ->
        :ok

      {:error, failures} ->
        Logger.error("[UpdateProgram] Update event dispatch had failures",
          program_id: program.id,
          errors: inspect(failures)
        )
    end
  end

  defp build_instructor_payload(nil), do: %{instructor: nil}

  defp build_instructor_payload(instructor) do
    %{
      instructor: %{
        name: instructor.name,
        headshot_url: instructor.headshot_url
      }
    }
  end

  @scheduling_fields ~w(meeting_days meeting_start_time meeting_end_time start_date end_date)a

  defp maybe_dispatch_schedule_event(original, updated) do
    changed? =
      Enum.any?(@scheduling_fields, fn field ->
        Map.get(original, field) != Map.get(updated, field)
      end)

    if changed? do
      event =
        ProgramEvents.program_schedule_updated(updated.id, %{
          provider_id: updated.provider_id,
          meeting_days: updated.meeting_days,
          meeting_start_time: updated.meeting_start_time,
          meeting_end_time: updated.meeting_end_time,
          start_date: updated.start_date,
          end_date: updated.end_date
        })

      case DomainEventBus.dispatch(KlassHero.ProgramCatalog, event) do
        :ok ->
          :ok

        {:error, failures} ->
          Logger.error("[UpdateProgram] Schedule event dispatch had failures",
            program_id: updated.id,
            errors: inspect(failures)
          )
      end
    end
  end
end
