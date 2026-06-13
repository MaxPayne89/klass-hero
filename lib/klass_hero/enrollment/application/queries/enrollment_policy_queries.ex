defmodule KlassHero.Enrollment.Application.Queries.EnrollmentPolicyQueries do
  @moduledoc """
  Query module for enrollment policy reads and capacity calculations.

  Centralises all read operations that depend on the enrollment policy repository,
  including single-program lookups, batch queries, and capacity calculations.
  """

  alias KlassHero.Enrollment.Domain.Models.EnrollmentPolicy

  @policy_repo Application.compile_env!(:klass_hero, [
                 :enrollment,
                 :for_querying_enrollment_policies
               ])

  @doc """
  Returns the enrollment policy for a program.
  """
  def get_enrollment_policy(program_id) when is_binary(program_id) do
    @policy_repo.get_by_program_id(program_id)
  end

  @doc """
  Returns remaining enrollment capacity for a program.

  Fetches the policy and active count, then delegates calculation to the
  domain model (`EnrollmentPolicy.remaining_capacity/2`).

  - `{:ok, non_neg_integer()}` — remaining spots
  - `{:ok, :unlimited}` — no maximum configured
  """
  def remaining_capacity(program_id) when is_binary(program_id) do
    case @policy_repo.get_by_program_id(program_id) do
      {:error, :not_found} ->
        {:ok, :unlimited}

      {:ok, policy} ->
        count = @policy_repo.count_active_enrollments(program_id)
        {:ok, EnrollmentPolicy.remaining_capacity(policy, count)}
    end
  end

  @doc """
  Returns remaining capacity for multiple programs in a single batch query.
  Returns a map of `program_id => remaining_count | :unlimited`.
  """
  def get_remaining_capacities(program_ids) when is_list(program_ids) do
    {policies, active_counts} = fetch_policies_and_active_counts(program_ids)

    Map.new(program_ids, fn id ->
      case Map.get(policies, id) do
        nil ->
          {id, :unlimited}

        policy ->
          count = Map.get(active_counts, id, 0)
          {id, EnrollmentPolicy.remaining_capacity(policy, count)}
      end
    end)
  end

  @doc """
  Returns the count of active (pending/confirmed) enrollments for a program.
  """
  def count_active_enrollments(program_id) when is_binary(program_id) do
    @policy_repo.count_active_enrollments(program_id)
  end

  @doc """
  Returns counts of active enrollments for multiple programs in a single batch query.
  Returns a map of `program_id => count`.
  """
  def count_active_enrollments_batch(program_ids) when is_list(program_ids) do
    @policy_repo.count_active_enrollments_batch(program_ids)
  end

  @doc """
  Returns enrollment summary (enrolled count + total capacity) for multiple programs
  using only 2 DB queries. Returns a map of `program_id => %{enrolled: integer, capacity: integer | nil}`.

  Use this instead of calling `get_remaining_capacities/1` and `count_active_enrollments_batch/1`
  separately — doing so would issue 3 DB queries for the same data.
  """
  def get_enrollment_summary_batch(program_ids) when is_list(program_ids) do
    {policies, active_counts} = fetch_policies_and_active_counts(program_ids)

    Map.new(program_ids, fn id ->
      active = Map.get(active_counts, id, 0)
      capacity = calculate_capacity(Map.get(policies, id), active)
      {id, %{enrolled: active, capacity: capacity}}
    end)
  end

  defp calculate_capacity(nil, _active), do: nil

  defp calculate_capacity(policy, active) do
    case EnrollmentPolicy.remaining_capacity(policy, active) do
      :unlimited -> nil
      remaining -> active + remaining
    end
  end

  # Shared by get_remaining_capacities/1 and get_enrollment_summary_batch/1 to prevent query drift.
  defp fetch_policies_and_active_counts(program_ids) do
    policies = @policy_repo.get_policies_by_program_ids(program_ids)
    active_counts = @policy_repo.count_active_enrollments_batch(program_ids)
    {policies, active_counts}
  end
end
