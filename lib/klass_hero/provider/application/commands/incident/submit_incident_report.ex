defmodule KlassHero.Provider.Application.Commands.Incident.SubmitIncidentReport do
  @moduledoc """
  Use case for a provider submitting an incident report.

  Validates input, verifies program-or-session ownership via Provider-local
  projections (no cross-context synchronous reads), optionally uploads a
  photo to private storage, and **atomically** persists the report row plus
  the notification-email Oban job. The `:incident_reported` domain event is
  dispatched after the transaction commits.

  Persistence and enqueue commit together — if either fails, the report row
  is rolled back, no email is scheduled, and any uploaded photo is deleted
  on a best-effort basis. This replaces a previous integration-event handler
  that enqueued the email job out-of-band; Postgres ACID covers the
  durability guarantee that handler used to provide.
  """

  alias KlassHero.Provider.Application.Queries.ProviderProgramQueries
  alias KlassHero.Provider.Domain.Events.ProviderEvents
  alias KlassHero.Provider.Domain.Models.IncidentReport
  alias KlassHero.Provider.Domain.Models.ProviderProfile
  alias KlassHero.Repo
  alias KlassHero.Shared.DomainEventBus
  alias KlassHero.Shared.Storage

  require Logger

  @context KlassHero.Provider

  @repository Application.compile_env!(:klass_hero, [:provider, :for_storing_incident_reports])
  @sessions_query Application.compile_env!(:klass_hero, [:provider, :for_querying_session_details])
  @profile_query Application.compile_env!(:klass_hero, [:provider, :for_querying_provider_profiles])
  @scheduler Application.compile_env!(:klass_hero, [:provider, :for_scheduling_incident_notifications])

  defguardp is_present(s) when is_binary(s) and byte_size(s) > 0

  @doc """
  Submits an incident report.

  ## Parameters

  - `:provider_profile_id` — Required. The provider submitting the report.
  - `:reporter_user_id` — Required. The user submitting the report.
  - `:reporter_display_name` — Required. Snapshot of the reporter's display name at submit time.
  - `:program_id` OR `:session_id` — Required. Exactly one must be set.
  - `:category` — Required. One of `IncidentReport.valid_categories/0`.
  - `:severity` — Required. One of `IncidentReport.valid_severities/0`.
  - `:description` — Required. Free-text (at least 10 characters).
  - `:occurred_at` — Required. `DateTime.t()` (cannot be in the future).
  - `:file_binary` — Optional. Binary content of an attached photo.
  - `:original_filename` — Optional. Original filename of the photo.
  - `:content_type` — Optional. MIME type of the photo (defaults to `image/jpeg`).
  - `:storage_opts` — Optional. Extra options passed to the storage adapter.

  ## Returns

  - `{:ok, IncidentReport.t()}` on success
  - `{:error, keyword() | Ecto.Changeset.t() | term()}` on validation,
    ownership, persistence, or enqueue failure
  """
  @spec execute(map()) ::
          {:ok, IncidentReport.t()}
          | {:error, keyword() | Ecto.Changeset.t() | term()}
  def execute(params) when is_map(params) do
    storage_opts = params[:storage_opts] || []

    with :ok <- validate_ownership(params),
         {:ok, profile} <- fetch_profile(params),
         {:ok, photo_ref} <- maybe_upload_photo(params),
         {:ok, report} <- build_report(params, photo_ref),
         {:ok, persisted} <- persist_and_enqueue(report, profile, photo_ref, storage_opts) do
      publish_event(persisted, profile)
      {:ok, persisted}
    end
  end

  # Read outside the transaction deliberately: `business_owner_email`/`business_name` are stable,
  # not mutated by the transaction, so the read-outside-tx rule (CLAUDE.md) does not apply.
  defp fetch_profile(%{provider_profile_id: id}) do
    case @profile_query.get(id) do
      {:ok, %ProviderProfile{} = profile} -> {:ok, profile}
      {:error, :not_found} -> {:error, [provider_profile_id: "does not exist"]}
    end
  end

  # Ownership enforced via Provider-local projection — no cross-context sync read.
  defp validate_ownership(%{program_id: pid, provider_profile_id: prov_id}) when is_binary(pid) do
    case ProviderProgramQueries.get_by_id(pid) do
      {:ok, %{provider_id: ^prov_id}} -> :ok
      _ -> {:error, [program_id: "does not belong to this provider"]}
    end
  end

  defp validate_ownership(%{session_id: sid, provider_profile_id: prov_id}) when is_binary(sid) do
    case @sessions_query.get_by_id(sid) do
      {:ok, %{provider_id: ^prov_id}} -> :ok
      _ -> {:error, [session_id: "does not belong to this provider"]}
    end
  end

  defp validate_ownership(_), do: {:error, [target: "exactly one of program_id or session_id must be set"]}

  defp maybe_upload_photo(%{file_binary: nil}), do: {:ok, %{photo_url: nil, original_filename: nil}}

  # Filename validated before the storage call to avoid orphaning an upload if the domain model rejects it.
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

  defp build_report(params, %{photo_url: url, original_filename: name}) do
    IncidentReport.new(%{
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

  # Row insert and email-job insert commit together via ACID — replaces an out-of-band integration event handler.
  defp persist_and_enqueue(report, profile, photo_ref, storage_opts) do
    fn ->
      with {:ok, persisted} <- @repository.create(report),
           :ok <- maybe_schedule_notification(persisted, profile) do
        persisted
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end
    |> Repo.transaction()
    |> finalise_transaction(photo_ref, storage_opts)
  end

  # Skip when reporter is the owner (noise) or when there is no email address to notify.
  defp maybe_schedule_notification(%IncidentReport{reporter_user_id: rid}, %ProviderProfile{identity_id: rid}), do: :ok

  defp maybe_schedule_notification(_report, %ProviderProfile{business_owner_email: email}) when not is_present(email),
    do: :ok

  defp maybe_schedule_notification(report, %ProviderProfile{} = profile) do
    case @scheduler.schedule(report, profile) do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp finalise_transaction({:ok, _persisted} = ok, _photo_ref, _storage_opts), do: ok

  defp finalise_transaction({:error, _reason} = err, photo_ref, storage_opts) do
    cleanup_photo(photo_ref, storage_opts)
    err
  end

  # Rollback only undoes DB writes; storage is external and would leave an orphan blob without this cleanup.
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

  defp publish_event(report, profile) do
    event = ProviderEvents.incident_reported(report, profile)
    DomainEventBus.dispatch(@context, event)
  end
end
