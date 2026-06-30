defmodule KlassHero.Participation.Application.Queries.ListProviderSessions do
  @moduledoc """
  Use case for listing sessions for a specific provider on a date.

  Used by provider dashboard to show their assigned sessions.
  """

  alias KlassHero.Participation.ProgramSession

  @session_repository Application.compile_env!(:klass_hero, [:participation, :for_querying_sessions])

  @type params :: %{
          required(:provider_id) => String.t(),
          optional(:date) => Date.t()
        }

  @type result :: {:ok, [ProgramSession.t()]}

  @doc """
  Lists sessions for a provider on a specific date.

  ## Parameters

  - `params` - Map containing:
    - `provider_id` - ID of the provider
    - `date` - Date to filter by (defaults to today)

  ## Returns

  `{:ok, sessions}` - List of sessions assigned to the provider.
  """
  @spec execute(params()) :: result()
  def execute(%{provider_id: provider_id} = params) do
    date = Map.get(params, :date, Date.utc_today())
    sessions = @session_repository.list_by_provider_and_date(provider_id, date)
    {:ok, sessions}
  end
end
