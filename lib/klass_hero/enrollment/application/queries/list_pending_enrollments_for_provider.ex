defmodule KlassHero.Enrollment.Application.Queries.ListPendingEnrollmentsForProvider do
  @moduledoc """
  Lists enriched pending enrollment entries for a provider's programs.

  Single repo round-trip filters by `status: :pending` and any of the given
  program IDs. Enrichment resolves child names (Family ACL), parent IDs, and
  program titles (ProgramCatalog ACL) for display. Missing metadata falls back
  to "Unknown" so a stale ACL row never breaks the dashboard.
  """

  import Ecto.Query, only: [from: 2]

  require Logger

  @enrollment_reader Application.compile_env!(:klass_hero, [
                       :enrollment,
                       :for_querying_enrollments
                     ])
  @child_info_adapter Application.compile_env!(:klass_hero, [
                        :enrollment,
                        :for_resolving_child_info
                      ])

  @type entry :: %{
          enrollment_id: String.t(),
          program_id: String.t(),
          program_title: String.t(),
          child_id: String.t(),
          child_name: String.t(),
          parent_id: String.t(),
          enrolled_at: DateTime.t()
        }

  @spec execute([binary()]) :: [entry()]
  def execute([]), do: []

  def execute(program_ids) when is_list(program_ids) do
    Logger.info("[Enrollment.ListPendingEnrollmentsForProvider] Listing",
      program_count: length(program_ids)
    )

    case @enrollment_reader.list_pending_by_programs(program_ids) do
      [] ->
        []

      enrollments ->
        child_ids = enrollments |> Enum.map(& &1.child_id) |> Enum.uniq()
        children = @child_info_adapter.get_children_by_ids(child_ids)
        child_map = Map.new(children, fn c -> {c.id, c} end)

        program_map = program_titles_map(program_ids)

        Enum.map(enrollments, &build_entry(&1, child_map, program_map))
    end
  end

  defp program_titles_map(program_ids) do
    # Trigger: ProgramCatalog depends on Enrollment (for capacity ACL), so calling
    #          back into ProgramCatalog would create a dependency cycle.
    # Why: query the `programs` table directly — acceptable in the query layer,
    #      mirrors the approach in ProgramCatalogACL.
    # Outcome: returns a map of %{program_id_string => title}
    valid_ids =
      program_ids
      |> Enum.filter(fn id -> match?({:ok, _}, Ecto.UUID.cast(id)) end)

    case valid_ids do
      [] ->
        %{}

      ids ->
        from(p in "programs",
          where: p.id in ^Enum.map(ids, &Ecto.UUID.dump!/1),
          select: {type(p.id, :binary_id), p.title}
        )
        |> KlassHero.Repo.all()
        |> Map.new()
    end
  end

  defp build_entry(enrollment, child_map, program_map) do
    child_name =
      case Map.get(child_map, enrollment.child_id) do
        nil -> "Unknown"
        child -> "#{child.first_name} #{child.last_name}"
      end

    program_title = Map.get(program_map, enrollment.program_id, "Unknown")

    %{
      enrollment_id: enrollment.id,
      program_id: enrollment.program_id,
      program_title: program_title,
      child_id: enrollment.child_id,
      child_name: child_name,
      parent_id: enrollment.parent_id,
      enrolled_at: enrollment.enrolled_at
    }
  end
end
