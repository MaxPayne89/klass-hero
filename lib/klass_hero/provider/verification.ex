defmodule KlassHero.Provider.Verification do
  @moduledoc """
  Verification document commands and queries for the Provider context.

  Covers provider-side submission and the admin review workflow (approve /
  reject, listing, and signed-URL previews). Reached through
  `KlassHero.Provider`'s public API.
  """

  use KlassHero.Shared.Tracing

  import Ecto.Query, warn: false

  alias KlassHero.Provider.ProviderProfile
  alias KlassHero.Provider.VerificationDocument
  alias KlassHero.Provider.Vetting
  alias KlassHero.Provider.VettingVerificationSync
  alias KlassHero.Repo
  alias KlassHero.Shared.Storage

  require Logger

  @required_verification_fields ~w(provider_profile_id original_filename document_type)a

  @doc """
  Submit a verification document for a provider.

  Accepts a map with:
  - `:provider_profile_id` - Required provider profile ID
  - `:document_type` - Required document type
  - `:file_binary` - Required binary content of the uploaded file
  - `:original_filename` - Required original filename
  - `:content_type` - Optional MIME type
  - `:storage_opts` - Optional keyword list of additional storage adapter options
  """
  def submit_verification_document(params) do
    context_span entity: "verification_document" do
      with :ok <- reject_dedicated_command(params[:document_type]),
           :ok <- validate_verification_submission(params),
           {:ok, file_url} <- upload_document_file(params) do
        insert_verification_document(params, file_url)
      end
    end
  end

  # A type with a dedicated command (business registration) captures structured facts the generic
  # path can't, so it must never be submitted here — enforced in the domain, not just the picker UI.
  # The dedicated command itself calls insert_verification_document/2 directly, bypassing this guard.
  defp reject_dedicated_command(document_type) do
    if VerificationDocument.dedicated_command?(document_type),
      do: {:error, :dedicated_submission_required},
      else: :ok
  end

  @doc """
  Uploads a document's binary to private storage and returns its stored `file_url`.

  Exposed so composite commands (e.g. business registration, which writes provider fields
  and the document row in one transaction) can perform the non-transactional storage upload
  *before* opening their DB transaction — storage is not transactional, so it must never sit
  inside `Repo.transaction`.
  """
  @spec upload_document_file(map()) :: {:ok, String.t()} | {:error, term()}
  def upload_document_file(params) do
    path =
      Storage.build_timestamped_path(
        "verification-docs/providers",
        params[:provider_profile_id],
        params[:original_filename],
        "document.pdf"
      )

    opts =
      [content_type: params[:content_type] || "application/octet-stream"]
      |> Keyword.merge(Map.get(params, :storage_opts, []))

    Storage.upload(:private, path, params[:file_binary], opts)
  end

  @doc "Approves a verification document (admin only)."
  def approve_verification_document(document_id, reviewer_id) do
    context_span entity: "verification_document" do
      with {:ok, doc} <- get_verification_document(document_id),
           {:ok, approved} <- VerificationDocument.approve(doc, reviewer_id),
           {:ok, persisted} <- review_and_sync_vetting(doc, approved, reviewer_id) do
        VettingVerificationSync.broadcast_updated(persisted.provider_profile_id)
        {:ok, persisted}
      end
    end
  end

  @doc "Rejects a verification document with reason (admin only)."
  def reject_verification_document(document_id, reviewer_id, reason) do
    context_span entity: "verification_document" do
      with :ok <- validate_rejection_reason(reason),
           {:ok, doc} <- get_verification_document(document_id),
           {:ok, rejected} <- VerificationDocument.reject(doc, reviewer_id, reason),
           {:ok, persisted} <- review_and_sync_vetting(doc, rejected, reviewer_id) do
        VettingVerificationSync.broadcast_updated(persisted.provider_profile_id)
        {:ok, persisted}
      end
    end
  end

  # The review and the vetting step it moves are one fact. They used to be two: the
  # review committed on its own and a bus handler advanced the step afterwards,
  # fire-and-forget on a `:normal` event with no retry behind it — so a failure there
  # left a document reading "approved" whose step never advanced, logged and lost.
  #
  # `Vetting` decides approve-vs-reset from the document's persisted status, so this
  # needs no decision argument of its own.
  defp review_and_sync_vetting(original, updated, reviewer_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:review, fn _repo, _changes -> persist_verification_review(original, updated) end)
    |> Ecto.Multi.run(:vetting, fn _repo, %{review: persisted} ->
      with :ok <- sync_vetting_step(persisted, reviewer_id), do: {:ok, :synced}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{review: persisted}} -> {:ok, persisted}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp sync_vetting_step(%VerificationDocument{status: :approved} = doc, reviewer_id) do
    Vetting.advance_step_for_document(doc.provider_profile_id, reviewer_id, to_string(doc.document_type), doc.id)
  end

  defp sync_vetting_step(%VerificationDocument{} = doc, reviewer_id) do
    Vetting.reset_step_for_document(doc.provider_profile_id, reviewer_id, to_string(doc.document_type))
  end

  @doc "Returns all verification documents for a provider."
  @spec get_provider_verification_documents(String.t()) :: {:ok, [VerificationDocument.t()]}
  def get_provider_verification_documents(provider_profile_id) when is_binary(provider_profile_id) do
    docs =
      VerificationDocument
      |> where([d], d.provider_profile_id == ^provider_profile_id)
      |> order_by([d], desc: d.inserted_at)
      |> Repo.all()

    {:ok, docs}
  end

  @doc "Lists all pending verification documents (admin)."
  @spec list_pending_verification_documents() :: {:ok, [VerificationDocument.t()]}
  def list_pending_verification_documents do
    docs =
      VerificationDocument
      |> where([d], d.status == :pending)
      |> order_by([d], asc: d.inserted_at)
      |> Repo.all()

    {:ok, docs}
  end

  @doc """
  List verification documents with provider info for admin review.

  Accepts an optional status filter atom:
  - `nil` - All documents (newest first)
  - `:pending` - Pending documents (oldest first, FIFO)
  - `:approved` - Approved documents (newest first)
  - `:rejected` - Rejected documents (newest first)
  """
  @spec list_verification_documents_for_admin(VerificationDocument.status() | nil) ::
          {:ok, [VerificationDocument.admin_review_result()]}
  def list_verification_documents_for_admin(status \\ nil) do
    results =
      status
      |> admin_review_query()
      |> Repo.all()
      |> Enum.map(&to_admin_review_result/1)

    {:ok, results}
  end

  @doc "Returns a single verification document with provider info for admin review."
  @spec get_verification_document_for_admin(String.t()) ::
          {:ok, VerificationDocument.admin_review_result()} | {:error, :not_found}
  def get_verification_document_for_admin(document_id) do
    admin_review_base_query()
    |> where([d], d.id == ^document_id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      row -> {:ok, to_admin_review_result(row)}
    end
  end

  @doc """
  Get a verification document with a verified preview URL for admin review.
  """
  @spec get_verification_document_preview(String.t()) ::
          {:ok,
           %{
             document: VerificationDocument.t(),
             provider_business_name: String.t(),
             legal_business_name: String.t() | nil,
             registration_number: String.t() | nil,
             signed_url: String.t() | nil,
             preview_type: :image | :pdf | :other
           }}
          | {:error, :not_found}
  def get_verification_document_preview(document_id) do
    with {:ok, result} <- get_verification_document_for_admin(document_id) do
      signed_url = verified_preview_url(result.document.file_url)
      preview_type = verification_preview_type(result.document.original_filename)
      {:ok, Map.merge(result, %{signed_url: signed_url, preview_type: preview_type})}
    end
  end

  @doc "Returns the list of valid verification document types."
  defdelegate valid_document_types, to: VerificationDocument
  defdelegate valid_document_types(entity_type), to: VerificationDocument

  @doc "Returns the document types submittable through the generic picker for a track."
  defdelegate generic_document_types(entity_type), to: VerificationDocument

  defp validate_verification_submission(params) do
    errors =
      Enum.reduce(@required_verification_fields, [], fn field, acc ->
        case params[field] do
          val when is_binary(val) and byte_size(val) > 0 -> acc
          _ -> [{field, "is required"} | acc]
        end
      end)

    errors =
      if is_nil(params[:file_binary]), do: [{:file_binary, "is required"} | errors], else: errors

    # Insurance certificates must carry an expiry date (B3, #957); the domain owns which types
    # require one, so this stays a per-type rule rather than a blanket changeset validation.
    errors =
      if VerificationDocument.expiry_required?(params[:document_type]) and is_nil(params[:expiry_date]) do
        [{:expiry_date, "is required"} | errors]
      else
        errors
      end

    case errors do
      [] -> :ok
      _ -> {:error, errors}
    end
  end

  @doc """
  Inserts a verification-document row from `params` and a stored `file_url`.

  Exposed alongside `upload_document_file/1` so composite commands (e.g. business
  registration, which writes provider fields and the document row in one transaction)
  reuse the single document-row shape instead of re-implementing it. `params` supplies
  `:provider_profile_id`, `:document_type`, and `:original_filename`.
  """
  @spec insert_verification_document(map(), String.t()) ::
          {:ok, VerificationDocument.t()} | {:error, Ecto.Changeset.t()}
  def insert_verification_document(params, file_url) do
    %{
      provider_profile_id: params[:provider_profile_id],
      document_type: params[:document_type],
      file_url: file_url,
      original_filename: params[:original_filename],
      expiry_date: params[:expiry_date]
    }
    |> VerificationDocument.create_changeset()
    |> Repo.insert()
  end

  defp validate_rejection_reason(reason) when is_binary(reason) and byte_size(reason) > 0, do: :ok
  defp validate_rejection_reason(_), do: {:error, :reason_required}

  defp get_verification_document(id) do
    case Repo.get(VerificationDocument, id) do
      nil -> {:error, :not_found}
      doc -> {:ok, doc}
    end
  end

  # Persists the review decision by casting the transitioned fields onto the
  # original (still-pending) record, so Ecto sees a real status change.
  defp persist_verification_review(%VerificationDocument{} = original, %VerificationDocument{} = updated) do
    attrs = Map.take(updated, [:status, :rejection_reason, :reviewed_by_id, :reviewed_at])

    original
    |> VerificationDocument.review_changeset(attrs)
    |> Repo.update()
  end

  defp admin_review_base_query do
    from d in VerificationDocument,
      join: p in ProviderProfile,
      on: d.provider_profile_id == p.id,
      select: {d, p.business_name, p.legal_business_name, p.registration_number}
  end

  # :pending orders oldest-first (FIFO); nil and other statuses order newest-first.
  defp admin_review_query(nil), do: order_by(admin_review_base_query(), [d], desc: d.inserted_at)

  defp admin_review_query(:pending) do
    admin_review_base_query()
    |> where([d], d.status == :pending)
    |> order_by([d], asc: d.inserted_at)
  end

  defp admin_review_query(status) when is_atom(status) do
    admin_review_base_query()
    |> where([d], d.status == ^status)
    |> order_by([d], desc: d.inserted_at)
  end

  defp to_admin_review_result({%VerificationDocument{} = doc, business_name, legal_business_name, registration_number}) do
    %{
      document: doc,
      provider_business_name: business_name,
      legal_business_name: legal_business_name,
      registration_number: registration_number
    }
  end

  # Checks existence before signing: signed_url/3 is URL math and succeeds even
  # for missing files, which would render broken previews.
  defp verified_preview_url(file_url) when is_binary(file_url) do
    with {:ok, true} <- Storage.file_exists?(:private, file_url),
         {:ok, url} <- Storage.signed_url(:private, file_url, 900) do
      url
    else
      {:ok, false} ->
        Logger.warning("[Provider] Verification preview file not found in storage: #{file_url}")
        nil

      {:error, reason} ->
        Logger.error("[Provider] Failed to generate verification preview URL for #{file_url}: #{inspect(reason)}")

        nil
    end
  end

  defp verified_preview_url(_), do: nil

  defp verification_preview_type(filename) when is_binary(filename) do
    filename
    |> String.downcase()
    |> Path.extname()
    |> case do
      ext when ext in ~w(.jpg .jpeg .png .gif .webp) -> :image
      ".pdf" -> :pdf
      ext when ext in ~w(.mp4 .mov .webm) -> :video
      _ -> :other
    end
  end

  defp verification_preview_type(_), do: :other
end
