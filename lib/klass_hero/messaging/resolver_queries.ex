defmodule KlassHero.Messaging.ResolverQueries do
  @moduledoc """
  Queries for resolving staff information via ACL adapters.
  """

  alias KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.ProgramStaffParticipantRepository

  @doc """
  Returns the user IDs of active staff assigned to a program.

  ## Parameters
  - program_id: The program to look up staff for

  ## Returns
  - List of user ID strings
  """
  @spec get_active_staff_user_ids(String.t()) :: [String.t()]
  def get_active_staff_user_ids(program_id) do
    ProgramStaffParticipantRepository.get_active_staff_user_ids(program_id)
  end
end
