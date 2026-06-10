defmodule KlassHero.Family do
  @moduledoc """
  Public API for the Family bounded context.

  Manages parent profiles, children, consents, and referral codes.
  Split from the former Identity context to give Family its own
  bounded context with clear domain boundaries.

  ## Usage

      # Parent Profiles
      {:ok, parent} = Family.create_parent_profile(%{identity_id: "user-uuid"})
      {:ok, parent} = Family.get_parent_by_identity("user-uuid")
      true = Family.has_parent_profile?("user-uuid")

      # Children
      children = Family.get_children("parent-uuid")
      {:ok, child} = Family.get_child_by_id("child-uuid")
  """

  use Boundary,
    top_level?: true,
    deps: [KlassHero, KlassHero.Shared],
    exports: [
      Domain.Models.Child,
      Domain.Models.ParentProfile,
      Domain.Models.Consent,
      Adapters.Driven.Persistence.ChangeChild,
      # Schema exported for Enrollment's enrollment→parent_profile join
      Adapters.Driven.Persistence.Schemas.ParentProfileSchema,
      # Schemas exported for Backpex admin direct Ecto access (read-only compliance view)
      Adapters.Driven.Persistence.Schemas.ConsentSchema,
      Adapters.Driven.Persistence.Schemas.ChildSchema
    ]

  alias KlassHero.Family.Adapters.Driven.Persistence.ChangeChild
  alias KlassHero.Family.Application.Commands.AnonymizeUserData
  alias KlassHero.Family.Application.Commands.Children.CreateChild
  alias KlassHero.Family.Application.Commands.Children.DeleteChild
  alias KlassHero.Family.Application.Commands.Children.UpdateChild
  alias KlassHero.Family.Application.Commands.Consents.GrantConsent
  alias KlassHero.Family.Application.Commands.Consents.WithdrawConsent
  alias KlassHero.Family.Application.Commands.Parents.CreateParentProfile
  alias KlassHero.Family.Application.Queries.Children.ChildQueries
  alias KlassHero.Family.Application.Queries.Children.PrepareChildDeletion
  alias KlassHero.Family.Application.Queries.Consents.ConsentQueries
  alias KlassHero.Family.Application.Queries.ExportUserData
  alias KlassHero.Family.Application.Queries.Parents.ParentProfileQueries
  alias KlassHero.Family.Domain.Models.Child
  alias KlassHero.Family.Domain.Services.ReferralCodeGenerator

  # ===========================================================================
  # Commands
  # ===========================================================================

  @doc """
  Creates a new parent profile.

  Returns:
  - `{:ok, ParentProfile.t()}` - Parent profile created successfully
  - `{:error, :duplicate_resource}` - Parent profile already exists
  - `{:error, {:validation_error, errors}}` - Domain validation failed
  - `{:error, changeset}` - Persistence validation failed
  """
  def create_parent_profile(attrs) when is_map(attrs) do
    CreateParentProfile.execute(attrs)
  end

  @doc """
  Creates a new child for a parent.

  Returns:
  - `{:ok, Child.t()}` on success
  - `{:error, {:validation_error, errors}}` for domain validation failures
  - `{:error, changeset}` for persistence validation failures
  """
  def create_child(attrs) when is_map(attrs) do
    CreateChild.execute(attrs)
  end

  @doc """
  Updates an existing child.

  Returns:
  - `{:ok, Child.t()}` on success
  - `{:error, :not_found}` if child doesn't exist
  - `{:error, {:validation_error, errors}}` for domain validation failures
  - `{:error, changeset}` for persistence validation failures
  """
  def update_child(child_id, attrs) when is_binary(child_id) and is_map(attrs) do
    UpdateChild.execute(child_id, attrs)
  end

  @doc """
  Deletes a child by ID.

  Returns:
  - `:ok` on success
  - `{:error, :not_found}` if child doesn't exist
  """
  def delete_child(child_id) when is_binary(child_id) do
    DeleteChild.execute(child_id)
  end

  @doc """
  Grants a new consent for a child.

  Expects a map with :parent_id, :child_id, and :consent_type.
  """
  def grant_consent(attrs) when is_map(attrs) do
    GrantConsent.execute(attrs)
  end

  @doc """
  Withdraws the active consent for a child and consent type.
  """
  def withdraw_consent(child_id, consent_type) when is_binary(child_id) and is_binary(consent_type) do
    WithdrawConsent.execute(child_id, consent_type)
  end

  @doc """
  Anonymizes all Family-owned data for a user during GDPR account deletion.

  Looks up the user's parent profile, then for each child:
  1. Deletes all consent records
  2. Anonymizes child PII (names, emergency contact, support needs, allergies)
  3. Publishes `child_data_anonymized` event for downstream contexts

  Returns:
  - `{:ok, :no_data}` if user has no parent profile
  - `{:ok, %{children_anonymized: count, consents_deleted: count}}`
  """
  defdelegate anonymize_data_for_user(identity_id), to: AnonymizeUserData, as: :execute

  @doc """
  Generates a referral code for a user.

  Options:
  - `:location` - Location string (default: "BERLIN")
  - `:year_suffix` - Year suffix string (default: current year's last 2 digits)
  """
  def generate_referral_code(name, opts \\ []) when is_binary(name) do
    ReferralCodeGenerator.generate(name, opts)
  end

  # ===========================================================================
  # Queries
  # ===========================================================================

  @doc """
  Retrieves a parent profile by identity ID.

  Returns:
  - `{:ok, ParentProfile.t()}` - Parent profile found
  - `{:error, :not_found}` - No parent profile exists
  """
  def get_parent_by_identity(identity_id) when is_binary(identity_id) do
    ParentProfileQueries.get_by_identity(identity_id)
  end

  @doc """
  Checks if a parent profile exists for the given identity ID.
  """
  def has_parent_profile?(identity_id) when is_binary(identity_id) do
    ParentProfileQueries.has_profile?(identity_id)
  end

  @doc """
  Retrieves multiple parent profiles by their IDs.

  Missing or invalid IDs are silently excluded from the result.
  """
  def get_parents_by_ids(parent_ids) when is_list(parent_ids) do
    ParentProfileQueries.get_by_ids(parent_ids)
  end

  @doc """
  Lists all children for a parent, ordered by first name then last name.
  """
  def get_children(parent_id) when is_binary(parent_id) do
    ChildQueries.list_by_guardian(parent_id)
  end

  @doc """
  Retrieves a single child by ID.

  Returns:
  - `{:ok, Child.t()}` - Child found
  - `{:error, :not_found}` - No child exists or invalid UUID
  """
  def get_child_by_id(child_id) when is_binary(child_id) do
    ChildQueries.get_by_id(child_id)
  end

  @doc """
  Checks if a child has active enrollments before deletion.

  Returns:
  - `{:ok, :no_enrollments}` -- no active enrollments, safe to delete
  - `{:ok, :has_enrollments, program_titles}` -- child is enrolled in programs
  - `{:error, reason}` -- database or infrastructure error
  """
  def prepare_child_deletion(child_id) when is_binary(child_id) do
    PrepareChildDeletion.execute(child_id)
  end

  @doc """
  Retrieves multiple children by their IDs.

  Missing or invalid IDs are silently excluded from the result.
  """
  def get_children_by_ids(child_ids) when is_list(child_ids) do
    ChildQueries.list_by_ids(child_ids)
  end

  @doc """
  Returns a MapSet of child IDs that have active consent of the given type.
  """
  def children_with_active_consents(child_ids, consent_type) when is_list(child_ids) and is_binary(consent_type) do
    ConsentQueries.children_with_active_consents(child_ids, consent_type)
  end

  @doc """
  Returns a MapSet of child IDs for a given parent.
  """
  def get_child_ids_for_parent(parent_id) when is_binary(parent_id) do
    ChildQueries.child_ids_for_guardian(parent_id)
  end

  @doc """
  Checks if a child belongs to a specific parent.
  """
  def child_belongs_to_parent?(child_id, parent_id) when is_binary(child_id) and is_binary(parent_id) do
    ChildQueries.belongs_to_guardian?(child_id, parent_id)
  end

  @doc """
  Checks if a child has an active consent of the given type.
  """
  def child_has_active_consent?(child_id, consent_type) when is_binary(child_id) and is_binary(consent_type) do
    ConsentQueries.child_has_active_consent?(child_id, consent_type)
  end

  @doc """
  Exports all Family-owned personal data for a user.

  Returns `%{children: [...]}` when the user has a parent profile,
  or `%{}` when no parent profile exists.
  """
  defdelegate export_data_for_user(identity_id), to: ExportUserData, as: :execute

  # ===========================================================================
  # Forms
  # ===========================================================================

  @doc """
  Returns a changeset for tracking child form changes.

  Used by LiveView forms for `to_form()` and `phx-change` validation.
  """
  def change_child(attrs \\ %{})

  def change_child(attrs) when is_map(attrs) and not is_struct(attrs) do
    ChangeChild.execute(attrs)
  end

  def change_child(%Child{} = child) do
    ChangeChild.execute(child)
  end

  @doc """
  Returns a changeset for tracking child form changes on an existing child.
  """
  def change_child(%Child{} = child, attrs) when is_map(attrs) do
    ChangeChild.execute(child, attrs)
  end
end
