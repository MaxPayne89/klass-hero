defmodule KlassHero.Participation.Application.Queries.GetSessionWithRoster do
  @moduledoc """
  Use case for retrieving a session with its complete roster.

  Returns session details along with all registered children and their
  participation status. Child info is resolved via the Family context.
  """

  alias KlassHero.Participation.BehavioralNote
  alias KlassHero.Participation.ParticipationRecord
  alias KlassHero.Participation.ProgramSession

  @session_repository Application.compile_env!(:klass_hero, [:participation, :for_querying_sessions])
  @participation_repository Application.compile_env!(:klass_hero, [
                              :participation,
                              :for_querying_participation_records
                            ])
  @child_info_resolver Application.compile_env!(:klass_hero, [
                         :participation,
                         :for_resolving_child_info
                       ])
  @behavioral_note_repository Application.compile_env!(:klass_hero, [
                                :participation,
                                :for_querying_behavioral_notes
                              ])

  @type roster_entry :: %{
          record: ParticipationRecord.t(),
          child_name: String.t(),
          child_first_name: String.t(),
          child_last_name: String.t(),
          allergies: String.t() | nil,
          support_needs: String.t() | nil,
          emergency_contact: String.t() | nil,
          behavioral_notes: [BehavioralNote.t()]
        }

  @type result ::
          {:ok, %{session: ProgramSession.t(), roster: [roster_entry()]}}
          | {:error, :not_found}

  @spec execute(String.t()) :: result()
  def execute(session_id) when is_binary(session_id) do
    with {:ok, session} <- @session_repository.get_by_id(session_id) do
      records = @participation_repository.list_by_session(session_id)
      {child_info_map, notes_map} = batch_resolve(records)

      roster =
        Enum.map(records, fn record ->
          info = Map.get(child_info_map, record.child_id, unknown_child_info())
          notes = Map.get(notes_map, record.child_id, [])

          %{record: record}
          |> Map.merge(build_enrichment_fields(info, notes))
        end)

      {:ok, %{session: session, roster: roster}}
    end
  end

  @spec execute_enriched(String.t()) :: {:ok, map()} | {:error, :not_found}
  def execute_enriched(session_id) when is_binary(session_id) do
    with {:ok, session} <- @session_repository.get_by_id(session_id) do
      records = @participation_repository.list_by_session(session_id)
      {child_info_map, notes_map} = batch_resolve(records)

      enriched_records =
        Enum.map(records, fn record ->
          info = Map.get(child_info_map, record.child_id, unknown_child_info())
          notes = Map.get(notes_map, record.child_id, [])

          # Convert struct to plain map so presentation fields can be merged without struct enforcement.
          Map.from_struct(record)
          |> Map.merge(build_enrichment_fields(info, notes))
        end)

      program_name = @session_repository.get_program_name(session.program_id)

      enriched_session =
        Map.from_struct(session)
        |> Map.put(:participation_records, enriched_records)
        |> Map.put(:program_name, program_name)

      {:ok, enriched_session}
    end
  end

  # Batches child-info and notes resolution to avoid N+1 queries.
  defp batch_resolve(records) do
    child_ids = records |> Enum.map(& &1.child_id) |> Enum.uniq()
    child_info_map = @child_info_resolver.resolve_children_info(child_ids)

    # Behavioral notes are only visible when parent has consented — filter before fetching.
    consented_child_ids =
      child_info_map
      |> Enum.filter(fn {_id, info} -> info.has_consent? end)
      |> Enum.map(fn {id, _info} -> id end)

    notes_map =
      if consented_child_ids == [] do
        %{}
      else
        @behavioral_note_repository.list_approved_by_children(consented_child_ids)
      end

    {child_info_map, notes_map}
  end

  defp build_enrichment_fields(child_info, notes) do
    %{
      child_name: "#{child_info.first_name} #{child_info.last_name}",
      child_first_name: child_info.first_name,
      child_last_name: child_info.last_name,
      allergies: child_info.allergies,
      support_needs: child_info.support_needs,
      emergency_contact: child_info.emergency_contact,
      behavioral_notes: notes
    }
  end

  defp unknown_child_info do
    %{
      first_name: "Unknown",
      last_name: "Child",
      allergies: nil,
      support_needs: nil,
      emergency_contact: nil,
      has_consent?: false
    }
  end
end
