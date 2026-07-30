defmodule KlassHero.Enrollment.EnqueueInviteEmails do
  @moduledoc """
  Assigns invite tokens to pending bulk enrollment invites and enqueues the emails
  that carry them.

  Orchestrates: query pending invites -> resolve program names -> generate tokens ->
  bulk assign -> enqueue one `SendInviteEmailWorker` job per invite.

  The token assignment and the jobs commit together. A token written without its
  job is an invite nobody is ever told about; a job without its token sends a link
  that does not work.
  """

  alias KlassHero.Enrollment
  alias KlassHero.Enrollment.Adapters.Driven.ACL.ProgramCatalogACL
  alias KlassHero.Enrollment.Adapters.Driving.Workers.SendInviteEmailWorker
  alias KlassHero.Enrollment.BulkEnrollmentInvite
  alias KlassHero.Repo
  alias KlassHero.Shared.Tracing.Context

  require Logger

  @doc "Tokens and emails every pending invite across `program_ids`."
  @spec execute([binary()], binary()) :: :ok | {:error, term()}
  def execute(program_ids, provider_id) when is_list(program_ids) and is_binary(provider_id) do
    enqueue(program_ids, provider_id, & &1)
  end

  @doc """
  Same, but only `invite_id` gets a job.

  A resend still tokens every pending invite in the program — that is the query
  the batch path shares — but the provider asked about one invite, so the others
  keep waiting for their own trigger.
  """
  @spec execute_for_invite(binary(), binary(), binary()) :: :ok | {:error, term()}
  def execute_for_invite(program_id, provider_id, invite_id) when is_binary(invite_id) do
    enqueue([program_id], provider_id, fn pairs ->
      Enum.filter(pairs, fn {id, _name} -> id == invite_id end)
    end)
  end

  defp enqueue(program_ids, provider_id, select_jobs) do
    Repo.transaction(fn ->
      program_ids
      |> pending_pairs(provider_id)
      |> select_jobs.()
      |> insert_jobs()
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp pending_pairs(program_ids, provider_id) do
    case Enrollment.list_pending_invites_without_token(program_ids) do
      [] ->
        Logger.info("[Enrollment.EnqueueInviteEmails] No pending invites to process")
        []

      invites ->
        {:ok, pairs} = process_invites(invites, provider_id)
        pairs
    end
  end

  defp insert_jobs([]), do: :ok

  defp insert_jobs(pairs) do
    jobs =
      Enum.map(pairs, fn {invite_id, program_name} ->
        %{invite_id: invite_id, program_name: program_name}
        |> Context.inject_into_args()
        |> SendInviteEmailWorker.new()
      end)

    Oban.insert_all(jobs)
    Logger.info("[Enrollment.EnqueueInviteEmails] Enqueued invite emails", count: length(jobs))
    :ok
  end

  defp process_invites(invites, provider_id) do
    programs_by_id = build_programs_by_id(provider_id)

    id_token_pairs =
      Enum.map(invites, fn invite ->
        {invite.id, BulkEnrollmentInvite.generate_token()}
      end)

    {:ok, _count} = Enrollment.bulk_assign_invite_tokens(id_token_pairs)

    pairs =
      Enum.map(invites, fn invite ->
        program_name = Map.get(programs_by_id, invite.program_id, "Program")
        {invite.id, program_name}
      end)

    Logger.info("[Enrollment.EnqueueInviteEmails] Prepared invite emails",
      count: length(pairs)
    )

    {:ok, pairs}
  end

  defp build_programs_by_id(provider_id) do
    ProgramCatalogACL.list_program_titles_for_provider(provider_id)
    |> Map.new(fn {title, id} -> {id, title} end)
  end
end
