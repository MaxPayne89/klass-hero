defmodule KlassHero.Family do
  @moduledoc """
  Public API for the Family context.

  Manages parent profiles, children, consents, and referral codes. This module
  is the context's only seam: other contexts and the web layer call these
  functions and never reach into internals.

  ## Usage

      # Parent Profiles
      {:ok, parent} = Family.create_parent_profile(%{identity_id: "user-uuid"})
      {:ok, parent} = Family.get_parent_by_identity("user-uuid")
      true = Family.has_parent_profile?("user-uuid")

      # Children
      children = Family.get_children("parent-uuid")
      {:ok, child} = Family.get_child_by_id("child-uuid")
  """

  import Ecto.Query

  alias KlassHero.Family.Adapters.Driven.ACL.ChildEnrollmentACL
  alias KlassHero.Family.Adapters.Driven.ACL.ChildParticipationACL
  alias KlassHero.Family.Child
  alias KlassHero.Family.ChildGuardian
  alias KlassHero.Family.Consent
  alias KlassHero.Family.Domain.Events.FamilyEvents
  alias KlassHero.Family.Domain.Services.ReferralCodeGenerator
  alias KlassHero.Family.ParentProfile
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.EctoErrorHelpers
  alias KlassHero.Shared.EventDispatchHelper

  @context __MODULE__

  @doc """
  Creates a new parent profile.

  Returns:
  - `{:ok, ParentProfile.t()}` - Parent profile created successfully
  - `{:error, :duplicate_resource}` - Parent profile already exists
  - `{:error, {:validation_error, errors}}` - Domain validation failed
  - `{:error, changeset}` - Persistence validation failed
  """
  def create_parent_profile(attrs) when is_map(attrs) do
    %ParentProfile{}
    |> ParentProfile.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, parent} ->
        {:ok, parent}

      {:error, %Ecto.Changeset{errors: errors} = changeset} ->
        if EctoErrorHelpers.unique_constraint_violation?(errors, :identity_id) do
          {:error, :duplicate_resource}
        else
          {:error, changeset}
        end
    end
  end

  @doc """
  Creates a new child, optionally linking it to a guardian.

  Pass `:parent_id` in `attrs` to establish the guardian relationship; the
  child and the guardian link are then created atomically.

  Returns:
  - `{:ok, Child.t()}` on success
  - `{:error, changeset}` for validation failures
  """
  def create_child(attrs) when is_map(attrs) do
    {parent_id, child_attrs} = Map.pop(attrs, :parent_id)

    case insert_child(child_attrs, parent_id) do
      {:ok, child} ->
        dispatch_child_created(child, parent_id)
        {:ok, child}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  defp insert_child(attrs, nil) do
    %Child{}
    |> Child.changeset(attrs)
    |> Repo.insert()
  end

  defp insert_child(attrs, guardian_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:child, Child.changeset(%Child{}, attrs))
    |> Ecto.Multi.insert(:guardian_link, fn %{child: child} ->
      ChildGuardian.changeset(%ChildGuardian{}, %{
        child_id: child.id,
        guardian_id: guardian_id,
        relationship: "parent",
        is_primary: true
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{child: child}} -> {:ok, child}
      {:error, _step, %Ecto.Changeset{} = changeset, _changes} -> {:error, changeset}
    end
  end

  @doc """
  Updates an existing child.

  Returns:
  - `{:ok, Child.t()}` on success
  - `{:error, :not_found}` if the child doesn't exist
  - `{:error, changeset}` for validation failures
  """
  def update_child(child_id, attrs) when is_binary(child_id) and is_map(attrs) do
    with {:ok, child} <- fetch_child(child_id),
         {:ok, updated} <- child |> Child.changeset(attrs) |> Repo.update() do
      dispatch_child_updated(updated)
      {:ok, updated}
    end
  end

  @doc """
  Deletes a child and all associated records across contexts.

  Transaction order satisfies FK constraints:
  1. Delete consents (Family-owned, FK RESTRICT on child_id)
  2. Cancel active enrollments (cross-context via ACL)
  3. Delete behavioral notes + participation records (cross-context via ACL)
  4. Delete the child

  Returns `:ok`, or `{:error, :not_found}` if the child doesn't exist.
  """
  def delete_child(child_id) when is_binary(child_id) do
    Repo.transaction(fn ->
      with {:ok, _} <- tag_step(:delete_consents, delete_all_consents_for_child(child_id)),
           {:ok, _} <- tag_step(:cancel_enrollments, ChildEnrollmentACL.cancel_active_for_child(child_id)),
           {:ok, _} <- tag_step(:delete_participation, ChildParticipationACL.delete_all_for_child(child_id)),
           :ok <- tag_step(:delete_child, delete_child_record(child_id)) do
        :ok
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, {:delete_child, :not_found}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp delete_child_record(child_id) do
    case fetch_child(child_id) do
      {:ok, child} ->
        # Bare Repo.delete raises Ecto.ConstraintError on FK violations; changeset
        # wrapping converts them to {:error, changeset}. Constraints span Enrollment,
        # Participation, and Family.
        child
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.foreign_key_constraint(:id,
          name: "enrollments_child_id_fkey",
          message: "has associated enrollments"
        )
        |> Ecto.Changeset.foreign_key_constraint(:id,
          name: "participation_records_child_id_fkey",
          message: "has associated participation records"
        )
        |> Ecto.Changeset.foreign_key_constraint(:id,
          name: "consents_child_id_fkey",
          message: "has associated consents"
        )
        |> Ecto.Changeset.foreign_key_constraint(:id,
          name: "behavioral_notes_child_id_fkey",
          message: "has associated behavioral notes"
        )
        |> Repo.delete()
        |> case do
          {:ok, _deleted} -> :ok
          {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
        end

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  # Passes through success, tags errors with the step name for traceability.
  defp tag_step(_step, {:ok, _} = result), do: result
  defp tag_step(_step, :ok), do: :ok
  defp tag_step(step, {:error, reason}), do: {:error, {step, reason}}

  @doc """
  Grants a new consent for a child.

  Expects a map with `:parent_id`, `:child_id`, and `:consent_type`.
  """
  def grant_consent(attrs) when is_map(attrs) do
    attrs = Map.put_new(attrs, :granted_at, DateTime.utc_now())

    %Consent{}
    |> Consent.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, consent} ->
        {:ok, consent}

      {:error, %Ecto.Changeset{errors: errors} = changeset} ->
        # Partial unique index on (child_id, consent_type) WHERE withdrawn_at IS NULL.
        if EctoErrorHelpers.any_unique_constraint_violation?(errors) do
          {:error, :already_active}
        else
          {:error, changeset}
        end
    end
  end

  @doc """
  Withdraws the active consent for a child and consent type.

  Returns `{:ok, Consent.t()}`, or `{:error, :not_found}` when no active consent
  exists.
  """
  def withdraw_consent(child_id, consent_type) when is_binary(child_id) and is_binary(consent_type) do
    case active_consent(child_id, consent_type) do
      nil ->
        {:error, :not_found}

      consent ->
        consent
        |> Consent.withdraw_changeset(DateTime.utc_now() |> DateTime.truncate(:second))
        |> Repo.update()
    end
  end

  @doc """
  Anonymizes all Family-owned data for a user during GDPR account deletion.

  Looks up the user's parent profile, then for each child deletes all consent
  records, anonymizes child PII, and publishes `child_data_anonymized` so
  downstream contexts can anonymize their own data.

  Returns:
  - `{:ok, :no_data}` if the user has no parent profile
  - `{:ok, %{children_anonymized: count, consents_deleted: count}}`
  """
  def anonymize_data_for_user(identity_id) when is_binary(identity_id) do
    case get_parent_by_identity(identity_id) do
      {:ok, parent} -> anonymize_children_data(get_children(parent.id))
      {:error, :not_found} -> {:ok, :no_data}
    end
  end

  defp anonymize_children_data(children) do
    anonymized_attrs = Child.anonymized_attrs()

    Enum.reduce_while(children, {:ok, %{children_anonymized: 0, consents_deleted: 0}}, fn child, {:ok, acc} ->
      with {:ok, consent_count} <- delete_all_consents_for_child(child.id),
           {:ok, _anonymized} <- child |> Child.anonymize_changeset(anonymized_attrs) |> Repo.update(),
           :ok <- dispatch_child_anonymized(child.id) do
        {:cont,
         {:ok,
          %{
            acc
            | children_anonymized: acc.children_anonymized + 1,
              consents_deleted: acc.consents_deleted + consent_count
          }}}
      else
        {:error, reason} ->
          require Logger

          Logger.error("[Family] anonymize_children_data failed", child_id: child.id, reason: inspect(reason))
          {:halt, {:error, reason}}
      end
    end)
  end

  @doc """
  Generates a referral code for a user.

  Options:
  - `:location` - Location string (default: "BERLIN")
  - `:year_suffix` - Year suffix string (default: current year's last 2 digits)
  """
  def generate_referral_code(name, opts \\ []) when is_binary(name) do
    ReferralCodeGenerator.generate(name, opts)
  end

  @doc """
  Retrieves a parent profile by identity ID.

  Returns `{:ok, ParentProfile.t()}` or `{:error, :not_found}`.
  """
  def get_parent_by_identity(identity_id) when is_binary(identity_id) do
    case Repo.get_by(ParentProfile, identity_id: identity_id) do
      nil -> {:error, :not_found}
      parent -> {:ok, parent}
    end
  end

  @doc """
  Checks if a parent profile exists for the given identity ID.
  """
  def has_parent_profile?(identity_id) when is_binary(identity_id) do
    Repo.exists?(from(p in ParentProfile, where: p.identity_id == ^identity_id))
  end

  @doc """
  Retrieves multiple parent profiles by their IDs. Missing or invalid IDs are
  silently excluded.
  """
  def get_parents_by_ids(parent_ids) when is_list(parent_ids) do
    valid_ids = Enum.filter(parent_ids, &match?({:ok, _}, Ecto.UUID.dump(&1)))
    Repo.all(from(p in ParentProfile, where: p.id in ^valid_ids))
  end

  @doc """
  Lists all children for a parent, ordered by first name then last name.
  """
  def get_children(parent_id) when is_binary(parent_id) do
    from(c in Child,
      join: cg in ChildGuardian,
      on: c.id == cg.child_id,
      where: cg.guardian_id == ^parent_id,
      order_by: [asc: c.first_name, asc: c.last_name]
    )
    |> Repo.all()
  end

  @doc """
  Retrieves a single child by ID.

  Returns `{:ok, Child.t()}` or `{:error, :not_found}` (including invalid UUIDs).
  """
  def get_child_by_id(child_id) when is_binary(child_id) do
    fetch_child(child_id)
  end

  @doc """
  Checks if a child has active enrollments before deletion.

  Returns:
  - `{:ok, :no_enrollments}` -- safe to delete
  - `{:ok, :has_enrollments, program_titles}` -- child is enrolled in programs
  - `{:error, :enrollment_check_failed}` -- database or infrastructure error
  """
  def prepare_child_deletion(child_id) when is_binary(child_id) do
    case list_active_enrollments(child_id) do
      {:ok, []} -> {:ok, :no_enrollments}
      {:ok, enrollments} -> {:ok, :has_enrollments, Enum.map(enrollments, & &1.program_title)}
      {:error, reason} -> {:error, reason}
    end
  end

  # Repo.all/1 raises on DB errors; rescue to return a structured error.
  defp list_active_enrollments(child_id) do
    {:ok, ChildEnrollmentACL.list_active_with_program_titles(child_id)}
  rescue
    error ->
      require Logger

      Logger.error("[Family] enrollment check failed: #{inspect(error)}", child_id: child_id)
      {:error, :enrollment_check_failed}
  end

  @doc """
  Retrieves multiple children by their IDs. Missing or invalid IDs are silently
  excluded.
  """
  def get_children_by_ids(child_ids) when is_list(child_ids) do
    valid_ids = Enum.filter(child_ids, &match?({:ok, _}, Ecto.UUID.dump(&1)))

    from(c in Child, where: c.id in ^valid_ids)
    |> Repo.all()
  end

  @doc """
  Returns a MapSet of child IDs that have active consent of the given type.
  """
  def children_with_active_consents(child_ids, consent_type) when is_list(child_ids) and is_binary(consent_type) do
    active_consent_child_ids(child_ids, consent_type)
  end

  @doc """
  Returns a MapSet of child IDs for a given parent.
  """
  def get_child_ids_for_parent(parent_id) when is_binary(parent_id) do
    parent_id
    |> get_children()
    |> MapSet.new(& &1.id)
  end

  @doc """
  Checks if a child belongs to a specific parent.
  """
  def child_belongs_to_parent?(child_id, parent_id) when is_binary(child_id) and is_binary(parent_id) do
    from(cg in ChildGuardian, where: cg.child_id == ^child_id and cg.guardian_id == ^parent_id)
    |> Repo.exists?()
  end

  @doc """
  Checks if a child has an active consent of the given type.
  """
  def child_has_active_consent?(child_id, consent_type) when is_binary(child_id) and is_binary(consent_type) do
    active_consent(child_id, consent_type) != nil
  end

  @doc """
  Exports all Family-owned personal data for a user.

  Returns `%{children: [...]}` when the user has a parent profile, or `%{}`
  when no parent profile exists.
  """
  def export_data_for_user(identity_id) when is_binary(identity_id) do
    case get_parent_by_identity(identity_id) do
      {:ok, parent} ->
        children_data =
          parent.id
          |> get_children()
          |> Enum.map(fn child ->
            format_child_export(child, list_consents_by_child(child.id))
          end)

        %{children: children_data}

      {:error, :not_found} ->
        %{}
    end
  end

  defp format_child_export(child, consents) do
    %{
      id: child.id,
      first_name: child.first_name,
      last_name: child.last_name,
      date_of_birth: Date.to_iso8601(child.date_of_birth),
      emergency_contact: child.emergency_contact,
      support_needs: child.support_needs,
      allergies: child.allergies,
      created_at: format_datetime(child.inserted_at),
      updated_at: format_datetime(child.updated_at),
      consents: Enum.map(consents, &format_consent_export/1)
    }
  end

  defp format_consent_export(consent) do
    %{
      id: consent.id,
      consent_type: consent.consent_type,
      granted_at: format_datetime(consent.granted_at),
      withdrawn_at: format_datetime(consent.withdrawn_at),
      created_at: format_datetime(consent.inserted_at),
      updated_at: format_datetime(consent.updated_at)
    }
  end

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  @doc """
  Returns a changeset for tracking child form changes.

  Used by LiveView forms for `to_form/2` and `phx-change` validation.
  """
  def change_child(child_or_attrs \\ %{})

  def change_child(attrs) when is_map(attrs) and not is_struct(attrs) do
    Child.changeset(%Child{}, attrs)
  end

  def change_child(%Child{} = child) do
    Child.changeset(child, %{})
  end

  @doc """
  Returns a changeset for tracking changes on an existing child.
  """
  def change_child(%Child{} = child, attrs) when is_map(attrs) do
    Child.changeset(child, attrs)
  end

  # --- private: consents ---

  defp active_consent(child_id, consent_type) do
    Repo.one(
      from(c in Consent,
        where: c.child_id == ^child_id and c.consent_type == ^consent_type and is_nil(c.withdrawn_at),
        limit: 1
      )
    )
  end

  defp active_consent_child_ids(child_ids, consent_type) do
    from(c in Consent,
      where: c.child_id in ^child_ids and c.consent_type == ^consent_type and is_nil(c.withdrawn_at),
      select: c.child_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp delete_all_consents_for_child(child_id) do
    {count, _} = Repo.delete_all(from(c in Consent, where: c.child_id == ^child_id))
    {:ok, count}
  end

  defp list_consents_by_child(child_id) do
    Repo.all(
      from(c in Consent,
        where: c.child_id == ^child_id,
        order_by: [asc: c.consent_type, desc: c.granted_at]
      )
    )
  end

  # --- private: children ---

  # Ecto.UUID.dump/1 (not cast/1) rejects raw 16-byte binaries that aren't valid
  # textual UUIDs, so a malformed id yields :not_found instead of a CastError.
  defp fetch_child(child_id) do
    case Ecto.UUID.dump(child_id) do
      {:ok, _} ->
        case Repo.get(Child, child_id) do
          nil -> {:error, :not_found}
          child -> {:ok, child}
        end

      :error ->
        {:error, :not_found}
    end
  end

  defp dispatch_child_created(child, parent_id) do
    FamilyEvents.child_created(child.id, %{
      child_id: child.id,
      parent_id: parent_id,
      first_name: child.first_name,
      last_name: child.last_name
    })
    |> EventDispatchHelper.dispatch(@context)
  end

  defp dispatch_child_updated(child) do
    # Downstream contexts (e.g. Messaging) refresh local child name lookups.
    FamilyEvents.child_updated(child.id, %{
      child_id: child.id,
      first_name: child.first_name,
      last_name: child.last_name
    })
    |> EventDispatchHelper.dispatch(@context)
  end

  defp dispatch_child_anonymized(child_id) do
    FamilyEvents.child_data_anonymized(child_id)
    |> EventDispatchHelper.dispatch_or_error(@context)
  end
end
