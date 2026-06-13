defmodule KlassHero.Participation.Application.Queries.ListSessions do
  @moduledoc """
  Use case for listing sessions.

  Supports filtering by program or by date.
  """

  alias KlassHero.Participation.Domain.Models.ProgramSession

  @session_repository Application.compile_env!(:klass_hero, [:participation, :for_querying_sessions])

  @type params :: %{
          optional(:program_id) => String.t(),
          optional(:date) => Date.t()
        }

  @type result :: [ProgramSession.t()]

  @spec execute(params()) :: result()
  def execute(%{program_id: program_id}) when is_binary(program_id) do
    @session_repository.list_by_program(program_id)
  end

  def execute(%{date: %Date{} = date}) do
    @session_repository.list_today_sessions(date)
  end

  def execute(%{}) do
    @session_repository.list_today_sessions(Date.utc_today())
  end

  @doc """
  Lists sessions with enriched data for admin dashboard.

  Returns maps with program_name, provider_name, checked_in_count, total_count.
  """
  @spec execute_admin(map()) :: [map()]
  def execute_admin(filters \\ %{}) do
    # Default to today when no date filter is provided to avoid loading all sessions.
    filters =
      if not Map.has_key?(filters, :date) and
           not (Map.has_key?(filters, :date_from) and Map.has_key?(filters, :date_to)) do
        Map.put(filters, :date, Date.utc_today())
      else
        filters
      end

    @session_repository.list_admin_sessions(filters)
  end
end
