defmodule KlassHero.Enrollment.Application.Queries.CheckParticipantEligibility do
  @moduledoc """
  Checks whether a child is eligible to enroll in a program based on
  the program's participant policy (age, gender, grade restrictions).

  Returns `{:ok, :eligible}` when no policy exists or all checks pass.
  Returns `{:error, :ineligible, reasons}` with human-readable reason list.
  Returns `{:error, :not_found}` when the child does not exist.
  """

  alias KlassHero.Enrollment.Domain.Models.ParticipantPolicy

  require Logger

  @participant_policy_repository Application.compile_env!(:klass_hero, [
                                   :enrollment,
                                   :for_querying_participant_policies
                                 ])
  @participant_details_adapter Application.compile_env!(:klass_hero, [
                                 :enrollment,
                                 :for_resolving_participant_details
                               ])
  @program_schedule_adapter Application.compile_env!(:klass_hero, [
                              :enrollment,
                              :for_resolving_program_schedule
                            ])

  @spec execute(binary(), binary()) ::
          {:ok, :eligible} | {:error, :ineligible, [String.t()]} | {:error, term()}
  def execute(program_id, child_id) do
    case load_policy(program_id) do
      {:ok, :no_policy} ->
        {:ok, :eligible}

      {:ok, %ParticipantPolicy{} = policy} ->
        check_eligibility(policy, program_id, child_id)
    end
  end

  defp check_eligibility(policy, program_id, child_id) do
    with {:ok, details} <- @participant_details_adapter.get_participant_details(child_id),
         {:ok, reference_date} <- resolve_reference_date(policy, program_id) do
      age_months = ParticipantPolicy.age_in_months(details.date_of_birth, reference_date)

      participant = %{
        age_months: age_months,
        gender: details.gender,
        grade: details.school_grade
      }

      Logger.info(
        "[Enrollment.CheckParticipantEligibility] Checking eligibility",
        program_id: program_id,
        child_id: child_id
      )

      # Map domain {:error, reasons} → public 3-tuple {:error, :ineligible, reasons}.
      case ParticipantPolicy.eligible?(policy, participant) do
        {:ok, :eligible} -> {:ok, :eligible}
        {:error, reasons} -> {:error, :ineligible, reasons}
      end
    end
  end

  defp load_policy(program_id) do
    case @participant_policy_repository.get_by_program_id(program_id) do
      {:ok, policy} -> {:ok, policy}
      {:error, :not_found} -> {:ok, :no_policy}
    end
  end

  # Some programs (e.g. summer camps) evaluate age at program start, not at registration.
  defp resolve_reference_date(%ParticipantPolicy{eligibility_at: "program_start"}, program_id) do
    case @program_schedule_adapter.get_program_start_date(program_id) do
      {:ok, nil} -> {:ok, Date.utc_today()}
      {:ok, date} -> {:ok, date}
      {:error, _} -> {:ok, Date.utc_today()}
    end
  end

  defp resolve_reference_date(%ParticipantPolicy{}, _program_id) do
    {:ok, Date.utc_today()}
  end
end
