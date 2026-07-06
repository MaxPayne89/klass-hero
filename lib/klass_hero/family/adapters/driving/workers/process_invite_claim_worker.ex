defmodule KlassHero.Family.Adapters.Driving.Workers.ProcessInviteClaimWorker do
  @moduledoc """
  Oban worker that processes invite claims.

  Deserializes JSON args from the queue and delegates to the
  `ProcessInviteClaim` use case. The `family` queue runs with
  concurrency 1, serializing all invite processing globally
  to prevent duplicate child records from concurrent events.
  """

  use KlassHero.Shared.Tracing.TracedWorker,
    queue: :family,
    max_attempts: 3

  alias KlassHero.Family.ProcessInviteClaim

  @impl true
  def execute(%Oban.Job{args: args}) do
    with {:ok, attrs} <- deserialize_args(args),
         {:ok, _result} <- ProcessInviteClaim.execute(attrs) do
      :ok
    end
  end

  # Oban JSON args use string keys and ISO date strings; convert to atom keys and Date.
  defp deserialize_args(args) do
    with {:ok, date_of_birth} <- parse_date(args["child_date_of_birth"]) do
      {:ok,
       %{
         invite_id: args["invite_id"],
         user_id: args["user_id"],
         program_id: args["program_id"],
         child_first_name: args["child_first_name"],
         child_last_name: args["child_last_name"],
         child_date_of_birth: date_of_birth,
         school_grade: args["school_grade"],
         school_name: args["school_name"],
         medical_conditions: args["medical_conditions"],
         nut_allergy: args["nut_allergy"]
       }}
    end
  end

  defp parse_date(nil), do: {:ok, nil}

  defp parse_date(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        {:ok, date}

      {:error, _reason} ->
        {:error, {:invalid_date, date_string}}
    end
  end

  defp parse_date(%Date{} = date), do: {:ok, date}
  defp parse_date(other), do: {:error, {:invalid_date_type, other}}
end
