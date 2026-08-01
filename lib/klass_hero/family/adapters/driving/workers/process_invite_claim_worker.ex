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

  alias KlassHero.Enrollment
  alias KlassHero.Family.ProcessInviteClaim
  alias KlassHero.Shared.ChangesetErrors

  require Logger

  @impl true
  def execute(%Oban.Job{args: args} = job) do
    with {:ok, attrs} <- deserialize_args(args),
         {:ok, _result} <- ProcessInviteClaim.execute(attrs) do
      :ok
    else
      {:error, reason} = error ->
        if final_attempt?(job), do: fail_invite(args["invite_id"], reason)
        error
    end
  end

  # Only once Oban is done retrying. `registered -> :failed` is a one-way door — `:failed`
  # can only go back to `:pending` — so failing the invite on an earlier attempt would
  # destroy a claim that the next attempt heals.
  defp final_attempt?(%Oban.Job{attempt: attempt, max_attempts: max_attempts}), do: attempt >= max_attempts

  # The invite belongs to Enrollment, so this goes through its facade rather than touching
  # the schema. A rejected transition means the invite is already terminal — enrolled by a
  # retry Lifeline re-ran, or failed by an earlier pass — which is a fact, not a fault.
  defp fail_invite(invite_id, reason) when is_binary(invite_id) do
    case Enrollment.transition_invite(%{id: invite_id}, %{status: :failed, error_details: describe(reason)}) do
      {:ok, _invite} ->
        :ok

      {:error, transition_error} ->
        Logger.warning("[ProcessInviteClaimWorker] Invite already past :registered, not failing it",
          invite_id: invite_id,
          reason: inspect(transition_error)
        )

        :ok
    end
  end

  defp fail_invite(_invite_id, _reason), do: :ok

  # A provider reads this in the invites table, so it has to name what is wrong with the
  # row they uploaded. `inspect/1` of a changeset names it only to a developer.
  defp describe(%Ecto.Changeset{} = changeset) do
    changeset
    |> ChangesetErrors.field_list()
    |> Enum.map_join("; ", fn {field, message} -> "#{humanize_field(field)} #{message}" end)
  end

  defp describe(reason), do: inspect(reason)

  defp humanize_field(field) do
    field
    |> Atom.to_string()
    |> String.replace("_", " ")
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
         nut_allergy: args["nut_allergy"],
         consent_photo_marketing: args["consent_photo_marketing"],
         consent_photo_social_media: args["consent_photo_social_media"]
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
