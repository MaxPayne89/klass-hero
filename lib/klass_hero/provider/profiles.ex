defmodule KlassHero.Provider.Profiles do
  @moduledoc """
  Provider profile commands and queries for the Provider context.

  Owns profile creation, the draft → active completion flow, admin
  verify/unverify (which mutate the profile and publish verification events),
  and profile reads. Reached through `KlassHero.Provider`'s public API.
  """

  use KlassHero.Shared.Tracing

  import Ecto.Query, warn: false

  alias KlassHero.Provider.Domain.Events.ProviderEvents
  alias KlassHero.Provider.ProviderProfile
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.EctoErrorHelpers
  alias KlassHero.Shared.CommandResult
  alias KlassHero.Shared.Outbox

  # Fields a caller may change via update_provider_profile/2 (all other keys stripped).
  @context KlassHero.Provider

  @profile_update_fields ~w(description logo_url)a

  # Scalar fields re-cast when persisting a transitioned profile struct. identity_id
  # and id never change, so they stay out; Ecto only stages actual diffs.
  @profile_persist_fields ~w(business_name business_owner_email description phone website address logo_url verified verified_at verified_by_id categories profile_status entity_type)a

  @doc """
  Creates a new provider profile.
  """
  def create_provider_profile(attrs) when is_map(attrs) do
    context_span entity: "provider_profile" do
      attrs_with_id = Map.put_new(attrs, :id, Ecto.UUID.generate())

      with {:ok, _validated} <- ProviderProfile.new(attrs_with_id),
           {:ok, persisted} <- insert_provider_profile(attrs_with_id) do
        {:ok, persisted}
      else
        result -> CommandResult.wrap_validation_errors(result)
      end
    end
  end

  @doc """
  Creates a draft provider profile for a deliberate upgrade (#968, ADR-0005).

  Owns the draft-birth policy: `profile_status: :draft` (the completion flow
  collects real business details). Every post-ADR-0005 provider is a deliberate
  act, so there's no longer a creation origin to record (#970).

  Same returns as `create_provider_profile/1`.
  """
  @spec create_draft_provider_profile(String.t(), String.t() | nil, String.t() | nil) ::
          {:ok, ProviderProfile.t()} | {:error, term()}
  def create_draft_provider_profile(identity_id, business_name, business_owner_email) when is_binary(identity_id) do
    create_provider_profile(%{
      identity_id: identity_id,
      business_name: business_name,
      business_owner_email: business_owner_email,
      profile_status: :draft
    })
  end

  @doc """
  Updates an existing provider profile.
  """
  @spec update_provider_profile(String.t(), map()) ::
          {:ok, ProviderProfile.t()}
          | {:error, :not_found | {:validation_error, list()} | Ecto.Changeset.t()}
  def update_provider_profile(provider_id, attrs) when is_binary(provider_id) and is_map(attrs) do
    context_span entity: "provider_profile" do
      attrs = Map.take(attrs, @profile_update_fields)

      with {:ok, existing} <- get_provider_profile(provider_id),
           merged = Map.merge(Map.from_struct(existing), attrs),
           {:ok, _validated} <- ProviderProfile.new(merged),
           updated = struct(existing, attrs),
           {:ok, persisted} <- persist_provider_profile(existing, updated) do
        {:ok, persisted}
      else
        result -> CommandResult.wrap_validation_errors(result)
      end
    end
  end

  @doc """
  Completes a draft provider profile, transitioning `profile_status` from `:draft` to `:active`.
  Returns `{:error, :already_active}` if the profile is not in draft status.
  """
  @spec complete_provider_profile(String.t(), map()) ::
          {:ok, ProviderProfile.t()}
          | {:error, :not_found | :already_active | {:validation_error, list()} | Ecto.Changeset.t()}
  def complete_provider_profile(provider_id, attrs) when is_binary(provider_id) and is_map(attrs) do
    context_span entity: "provider_profile" do
      with {:ok, existing} <- get_provider_profile(provider_id),
           {:ok, completed} <- ProviderProfile.complete_profile(existing, attrs),
           {:ok, persisted} <- persist_provider_profile(existing, completed) do
        {:ok, persisted}
      else
        result -> CommandResult.wrap_validation_errors(result)
      end
    end
  end

  @doc "Verifies a provider (admin only)."
  def verify_provider(provider_id, admin_id) do
    context_span entity: "provider_profile" do
      with {:ok, profile} <- get_provider_profile(provider_id),
           {:ok, verified} <- ProviderProfile.verify(profile, admin_id),
           {:ok, {persisted, _events}} <- persist_with_verification_event(profile, verified, admin_id, :verified) do
        {:ok, persisted}
      end
    end
  end

  @doc "Unverifies a provider (admin only)."
  def unverify_provider(provider_id, admin_id) do
    context_span entity: "provider_profile" do
      with {:ok, profile} <- get_provider_profile(provider_id),
           {:ok, unverified} <- ProviderProfile.unverify(profile),
           {:ok, {persisted, _events}} <- persist_with_verification_event(profile, unverified, admin_id, :unverified) do
        {:ok, persisted}
      end
    end
  end

  @doc "Retrieves a provider profile by identity ID."
  def get_provider_by_identity(identity_id) when is_binary(identity_id) do
    case Repo.get_by(ProviderProfile, identity_id: identity_id) do
      nil -> {:error, :not_found}
      profile -> {:ok, profile}
    end
  end

  @doc "Returns true if a provider profile exists for the given identity ID."
  def has_provider_profile?(identity_id) when is_binary(identity_id) do
    Repo.exists?(from p in ProviderProfile, where: p.identity_id == ^identity_id)
  end

  @doc "Returns the provider profile by ID."
  @spec get_provider_profile(String.t()) :: {:ok, ProviderProfile.t()} | {:error, :not_found}
  def get_provider_profile(provider_id) when is_binary(provider_id) do
    case Repo.get(ProviderProfile, provider_id) do
      nil -> {:error, :not_found}
      profile -> {:ok, profile}
    end
  end

  @doc """
  Resolves business names for a batch of provider IDs.

  Returns a map of `provider_id => business_name`. Unknown IDs are omitted.
  Used by other contexts (e.g. Participation) that need human-readable provider
  names without reaching into the `ProviderProfile` schema.
  """
  @spec get_business_names([String.t()]) :: %{String.t() => String.t()}
  def get_business_names([]), do: %{}

  def get_business_names(provider_ids) when is_list(provider_ids) do
    from(p in ProviderProfile, where: p.id in ^provider_ids, select: {p.id, p.business_name})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Gets the user (identity) ID for a provider profile ID.

  Used by cross-context consumers (e.g. Messaging) to resolve
  `conversation.provider_id` (provider profile ID) back to a user ID
  for permission and authorization checks.

  Returns:
  - `{:ok, identity_id}` - The user ID that owns this provider profile
  - `{:error, :not_found}` - No provider profile exists with this ID
  """
  @spec get_identity_id_for_provider(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def get_identity_id_for_provider(provider_id) when is_binary(provider_id) do
    case get_provider_profile(provider_id) do
      {:ok, %ProviderProfile{identity_id: identity_id}} -> {:ok, identity_id}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  @doc "Lists all verified provider IDs (used by projections at bootstrap)."
  def list_verified_provider_ids do
    ids = Repo.all(from p in ProviderProfile, where: p.verified == true, select: p.id)
    {:ok, ids}
  end

  @doc "Returns a changeset for tracking provider profile form changes (for `to_form()` / `phx-change`)."
  @spec change_provider_profile(ProviderProfile.t(), map()) :: Ecto.Changeset.t()
  def change_provider_profile(%ProviderProfile{} = provider, attrs \\ %{}) do
    ProviderProfile.edit_changeset(provider, attrs)
  end

  @doc "Changeset for the profile completion form — casts a broader set of fields than `change_provider_profile/2`."
  @spec change_provider_profile_completion(ProviderProfile.t(), map()) :: Ecto.Changeset.t()
  def change_provider_profile_completion(%ProviderProfile{} = provider, attrs \\ %{}) do
    ProviderProfile.completion_changeset(provider, attrs)
  end

  # Persists a create by validating at the domain boundary, then mapping the
  # unique-identity violation back to the frozen :duplicate_resource contract
  # (ProviderEventHandler/Accounts depend on that literal atom).
  defp insert_provider_profile(attrs) do
    # `mode: :savepoint` so a unique-identity violation rolls back only to a
    # savepoint instead of poisoning an outer transaction — this runs inside
    # `ProcessedEventRepository.execute_atomically`'s txn on the
    # `:user_registered`/`:user_confirmed` compensation path (issue #1065).
    %ProviderProfile{}
    |> ProviderProfile.changeset(attrs)
    |> Repo.insert(mode: :savepoint)
    |> case do
      {:ok, profile} ->
        {:ok, profile}

      {:error, %Ecto.Changeset{errors: errors} = changeset} ->
        if EctoErrorHelpers.unique_constraint_violation?(errors, :identity_id) do
          {:error, :duplicate_resource}
        else
          {:error, changeset}
        end
    end
  end

  # Persists a transitioned profile by casting the changed scalar fields onto the
  # originally-loaded record, so Ecto sees real changes (and auto-bumps updated_at).
  defp persist_provider_profile(%ProviderProfile{} = original, %ProviderProfile{} = updated) do
    attrs = Map.take(updated, @profile_persist_fields)

    original
    |> ProviderProfile.changeset(attrs)
    |> Repo.update()
  end

  # These two build an Event directly rather than promoting a domain one —
  # the pre-existing bypass of the bus, and the shape everything ends up in.
  defp persist_with_verification_event(original, updated, admin_id, decision) do
    Outbox.transact(@context, fn ->
      with {:ok, persisted} <- persist_provider_profile(original, updated) do
        {:ok, persisted, [verification_event(persisted, admin_id, decision)]}
      end
    end)
  end

  defp verification_event(profile, admin_id, :verified), do: ProviderEvents.provider_verified(profile, admin_id)

  defp verification_event(profile, admin_id, :unverified), do: ProviderEvents.provider_unverified(profile, admin_id)
end
