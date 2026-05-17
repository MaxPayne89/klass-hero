defmodule KlassHero.Enrollment.Domain.Ports.ForQueryingEnrollments do
  @moduledoc """
  Read-only port for querying enrollments in the Enrollment bounded context.

  Defines the contract for enrollment read operations (CQRS query side).
  Write operations remain in `ForManagingEnrollments`.
  """

  alias KlassHero.Enrollment.Domain.Models.Enrollment

  @doc """
  Retrieves an enrollment by ID.

  Returns:
  - `{:ok, Enrollment.t()}` - Enrollment found
  - `{:error, :not_found}` - No enrollment exists with the given ID
  """
  @callback get_by_id(id :: binary()) ::
              {:ok, Enrollment.t()} | {:error, :not_found}

  @doc """
  Lists all enrollments for a parent.

  Returns list of Enrollment.t(), empty list if none found.
  Results are ordered by enrolled_at descending (most recent first).
  """
  @callback list_by_parent(parent_id :: binary()) :: [Enrollment.t()]

  @doc """
  Counts monthly bookings for a parent within a date range.

  Only counts active enrollments (pending or confirmed).

  Parameters:
  - parent_id: The parent's ID
  - start_date: Start of the date range (inclusive)
  - end_date: End of the date range (inclusive)

  Returns non-negative integer count.
  """
  @callback count_monthly_bookings(
              parent_id :: binary(),
              start_date :: Date.t(),
              end_date :: Date.t()
            ) :: non_neg_integer()

  @doc """
  Returns the identity IDs of parents with active enrollments for a program.

  Active enrollments are those with status "pending" or "confirmed".
  Returns a distinct list of identity_ids (user IDs).
  """
  @callback list_enrolled_identity_ids(program_id :: binary()) :: [String.t()]

  @doc """
  Checks if a parent (identified by identity_id) has an active enrollment
  in a program.

  Returns true if at least one active enrollment exists for the given
  program and parent identity.
  """
  @callback enrolled?(program_id :: binary(), identity_id :: binary()) :: boolean()

  @doc """
  Lists active enrollments for a program.

  Active enrollments are those with status "pending" or "confirmed".
  Returns list of Enrollment.t(), ordered by enrolled_at descending.
  """
  @callback list_by_program(program_id :: binary()) :: [Enrollment.t()]

  @doc """
  Returns all enrollments with status `:pending` that belong to any of the
  given program IDs.

  Empty list of program IDs short-circuits to an empty result.
  """
  @callback list_pending_by_programs(program_ids :: [binary()]) :: [Enrollment.t()]
end
