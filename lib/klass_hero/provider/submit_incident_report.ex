defmodule KlassHero.Provider.SubmitIncidentReport do
  @moduledoc """
  Orchestrates a provider submitting an incident report.

  Validates ownership via Provider-local projections (no cross-context
  synchronous reads), optionally uploads a photo to private storage, and
  **atomically** persists the report row plus the notification-email Oban job.

  Persistence and enqueue commit together — if either fails, the report row is
  rolled back, no email is scheduled, and any uploaded photo is deleted on a
  best-effort basis. Postgres ACID covers the durability guarantee.
  """

  alias KlassHero.Provider
  alias KlassHero.Provider.Adapters.Driving.Workers.NotifyIncidentReportedWorker
  alias KlassHero.Provider.IncidentReport
  alias KlassHero.Provider.Programs
  alias KlassHero.Provider.ProviderProfile
  alias KlassHero.Repo
  alias KlassHero.Shared.Storage
  alias KlassHero.Shared.Tracing.ObanEnqueue

  require Logger

  defguardp is_present(s) when is_binary(s) and byte_size(s) > 0

  @doc """
  Submits an incident report.

  Returns `{:ok, IncidentReport.t()}` on success, or `{:error, keyword() |
  Ecto.Changeset.t() | term()}` on ownership, upload, validation, persistence,
  or enqueue failure.
  """
  @spec execute(map()) ::
          {:ok, IncidentReport.t()}
          | {:error, keyword() | Ecto.Changeset.t() | term()}
  def execute(params) when is_map(params) do
    storage_opts = params[:storage_opts] || []

    with :ok <- validate_ownership(params),
         {:ok, profile} <- fetch_profile(params),
         {:ok, photo_ref} <- maybe_upload_photo(params) do
      params
      |> build_changeset(photo_ref)
      |> persist_and_enqueue(profile, photo_ref, storage_opts)
    end
  end

  # Read outside the transaction deliberately: business_owner_email/business_name
  # are stable, not mutated by the transaction.
  defp fetch_profile(%{provider_profile_id: id}) do
    case Provider.get_provider_profile(id) do
      {:ok, %ProviderProfile{} = profile} -> {:ok, profile}
      {:error, :not_found} -> {:error, [provider_profile_id: "does not exist"]}
    end
  end

  # Ownership enforced via Provider-local projections — no cross-context sync read.
  defp validate_ownership(%{program_id: pid, provider_profile_id: prov_id})
       when is_binary(pid) and is_binary(prov_id) do
    case Programs.get_provider_program(pid, prov_id) do
      {:ok, _owned} -> :ok
      {:error, :not_found} -> {:error, [program_id: "does not belong to this provider"]}
    end
  end

  # No provider to own it — same outcome as a foreign program.
  defp validate_ownership(%{program_id: pid}) when is_binary(pid),
    do: {:error, [program_id: "does not belong to this provider"]}

  defp validate_ownership(%{session_id: sid, provider_profile_id: prov_id}) when is_binary(sid) do
    case Programs.get_session_detail(sid) do
      {:ok, %{provider_id: ^prov_id}} -> :ok
      _ -> {:error, [session_id: "does not belong to this provider"]}
    end
  end

  defp validate_ownership(_), do: {:error, [target: "exactly one of program_id or session_id must be set"]}

  defp maybe_upload_photo(%{file_binary: nil}), do: {:ok, %{photo_url: nil, original_filename: nil}}

  # Filename validated before the storage call to avoid orphaning an upload.
  defp maybe_upload_photo(%{file_binary: file_binary, original_filename: filename} = params)
       when is_binary(file_binary) and is_binary(filename) and byte_size(filename) > 0 do
    path =
      Storage.build_timestamped_path(
        "incident-reports/providers",
        params.provider_profile_id,
        filename,
        "photo.jpg"
      )

    content_type = params[:content_type] || "image/jpeg"
    opts = Keyword.merge([content_type: content_type], params[:storage_opts] || [])

    with {:ok, key} <- Storage.upload(:private, path, file_binary, opts) do
      {:ok, %{photo_url: key, original_filename: filename}}
    end
  end

  defp maybe_upload_photo(%{file_binary: file_binary}) when is_binary(file_binary) do
    {:error, [original_filename: "is required when photo is uploaded"]}
  end

  defp maybe_upload_photo(_), do: {:ok, %{photo_url: nil, original_filename: nil}}

  defp build_changeset(params, %{photo_url: url, original_filename: name}) do
    IncidentReport.create_changeset(%{
      id: Ecto.UUID.generate(),
      provider_profile_id: params.provider_profile_id,
      reporter_user_id: params.reporter_user_id,
      reporter_display_name: params[:reporter_display_name],
      program_id: params[:program_id],
      session_id: params[:session_id],
      category: params.category,
      severity: params.severity,
      description: params.description,
      occurred_at: params.occurred_at,
      photo_url: url,
      original_filename: name
    })
  end

  # Row insert and email-job insert commit together via ACID.
  defp persist_and_enqueue(changeset, profile, photo_ref, storage_opts) do
    fn ->
      with {:ok, persisted} <- Repo.insert(changeset),
           :ok <- maybe_schedule_notification(persisted, profile) do
        persisted
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end
    |> Repo.transaction()
    |> finalise_transaction(photo_ref, storage_opts)
  end

  # Skip when reporter is the owner (noise) or when there is no email to notify.
  defp maybe_schedule_notification(%IncidentReport{reporter_user_id: rid}, %ProviderProfile{identity_id: rid}), do: :ok

  defp maybe_schedule_notification(_report, %ProviderProfile{business_owner_email: email}) when not is_present(email),
    do: :ok

  defp maybe_schedule_notification(%IncidentReport{id: id}, %ProviderProfile{} = profile) do
    case ObanEnqueue.with_context(NotifyIncidentReportedWorker, %{
           incident_report_id: id,
           business_owner_email: profile.business_owner_email,
           business_name: profile.business_name
         }) do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp finalise_transaction({:ok, _persisted} = ok, _photo_ref, _storage_opts), do: ok

  defp finalise_transaction({:error, _reason} = err, photo_ref, storage_opts) do
    cleanup_photo(photo_ref, storage_opts)
    err
  end

  # Rollback only undoes DB writes; storage is external and would leave an orphan.
  defp cleanup_photo(%{photo_url: nil}, _storage_opts), do: :ok

  defp cleanup_photo(%{photo_url: url}, storage_opts) when is_binary(url) do
    case Storage.delete(:private, url, storage_opts) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("[SubmitIncidentReport] photo cleanup failed after rollback",
          photo_url: url,
          reason: inspect(reason)
        )

        :ok
    end
  end
end
