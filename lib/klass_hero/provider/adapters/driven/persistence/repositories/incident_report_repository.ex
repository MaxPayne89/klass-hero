defmodule KlassHero.Provider.Adapters.Driven.Persistence.Repositories.IncidentReportRepository do
  @moduledoc """
  Ecto-based repository for incident reports.

  Implements both `ForStoringIncidentReports` (writes) and
  `ForQueryingIncidentReports` (reads). Domain mapping via
  `IncidentReportMapper`. Infrastructure errors crash and are handled
  by the supervision tree.
  """

  @behaviour KlassHero.Provider.Domain.Ports.ForQueryingIncidentReports
  @behaviour KlassHero.Provider.Domain.Ports.ForStoringIncidentReports

  use KlassHero.Shared.Interaction

  import Ecto.Query

  alias KlassHero.Provider.Adapters.Driven.Persistence.Mappers.IncidentReportMapper
  alias KlassHero.Provider.Adapters.Driven.Persistence.Mappers.IncidentReportSummaryMapper
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.IncidentReportSchema
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.ProviderSessionDetailSchema
  alias KlassHero.Provider.Domain.Ports.ForQueryingIncidentReports
  alias KlassHero.Provider.Domain.Ports.ForStoringIncidentReports
  alias KlassHero.Repo

  @impl ForStoringIncidentReports
  @doc """
  Creates a new incident report in the database.

  Returns:
  - `{:ok, IncidentReport.t()}` on success
  - `{:error, Ecto.Changeset.t()}` on validation or FK failure
  """
  def create(report) do
    db_interaction operation: :create, entity: "incident_report" do
      attrs = IncidentReportMapper.to_schema(report)
      changeset = IncidentReportSchema.changeset(%IncidentReportSchema{}, attrs)

      with {:ok, saved} <- Repo.insert(changeset) do
        {:ok, IncidentReportMapper.to_domain(saved)}
      end
    end
  end

  @impl ForQueryingIncidentReports
  @doc """
  Retrieves an incident report by its ID.

  Returns:
  - `{:ok, IncidentReport.t()}` when found
  - `{:error, :not_found}` when no report exists with the given ID
  """
  def get(id) when is_binary(id) do
    db_interaction operation: :get, entity: "incident_report" do
      case Repo.get(IncidentReportSchema, id) do
        nil -> {:error, :not_found}
        schema -> {:ok, IncidentReportMapper.to_domain(schema)}
      end
    end
  end

  @impl ForQueryingIncidentReports
  @doc """
  Lists incident report summaries for a program owned by `provider_id`.

  Two-source query: program-direct reports (matched by
  `incident_reports.program_id`) plus session-linked reports (matched by
  joining `incident_reports.session_id` against the Provider-local
  `provider_session_details` projection). Both branches filter by
  `provider_id` for IDOR defense.
  """
  def list_for_program(provider_id, program_id) when is_binary(provider_id) and is_binary(program_id) do
    db_interaction operation: :list_for_program, entity: "incident_report_summary" do
      program_direct = list_program_direct(provider_id, program_id)
      session_linked = list_session_linked(provider_id, program_id)

      (program_direct ++ session_linked)
      |> Enum.sort_by(& &1.occurred_at, {:desc, DateTime})
      |> Enum.map(&IncidentReportSummaryMapper.from_schema/1)
    end
  end

  defp list_program_direct(provider_id, program_id) do
    from(r in IncidentReportSchema,
      where: r.provider_id == ^provider_id and r.program_id == ^program_id
    )
    |> Repo.all()
  end

  defp list_session_linked(provider_id, program_id) do
    from(r in IncidentReportSchema,
      join: s in ProviderSessionDetailSchema,
      on: s.session_id == r.session_id,
      where:
        r.provider_id == ^provider_id and
          s.provider_id == ^provider_id and
          s.program_id == ^program_id,
      select: r
    )
    |> Repo.all()
  end
end
