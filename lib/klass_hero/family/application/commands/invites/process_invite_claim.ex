defmodule KlassHero.Family.Application.Commands.Invites.ProcessInviteClaim do
  @moduledoc """
  Use case for processing an invite claim into a family unit.

  Orchestrates: ensure parent profile, find-or-create child, publish
  `invite_family_ready` event. Called by the Oban worker, which serializes
  execution via a single-concurrency queue to prevent duplicate children.
  """

  alias KlassHero.Family.Domain.Events.FamilyEvents
  alias KlassHero.Family.Domain.Models.Child
  alias KlassHero.Family.Domain.Models.ParentProfile
  alias KlassHero.Shared.CommandResult
  alias KlassHero.Shared.EventDispatchHelper

  require Logger

  @child_query Application.compile_env!(:klass_hero, [:family, :for_querying_children])
  @child_repository Application.compile_env!(:klass_hero, [:family, :for_storing_children])
  @parent_query Application.compile_env!(:klass_hero, [:family, :for_querying_parent_profiles])
  @parent_repository Application.compile_env!(:klass_hero, [:family, :for_storing_parent_profiles])

  @doc """
  Processes an invite claim by setting up the family unit.

  Expects a map with:
  - `:invite_id` - The invite being claimed
  - `:user_id` - The claiming user's identity ID
  - `:program_id` - The program the child is being enrolled in
  - `:child_first_name`, `:child_last_name`, `:child_date_of_birth` - Child identity
  - `:school_grade`, `:school_name`, `:medical_conditions`, `:nut_allergy` - Optional fields

  Returns:
  - `{:ok, %{parent: ParentProfile.t(), child: Child.t()}}` on success
  - `{:error, reason}` on failure
  """
  def execute(attrs) when is_map(attrs) do
    user_id = Map.fetch!(attrs, :user_id)
    invite_id = Map.fetch!(attrs, :invite_id)
    program_id = Map.fetch!(attrs, :program_id)

    # Trigger: parent and child are already committed at this point
    # Why: event dispatch is not transactional (PubSub); if it fails, Oban retries
    # Outcome: retry is safe because ensure_parent_profile and find_or_create_child
    #   are idempotent -- they find existing records, no duplicates created
    with {:ok, parent} <- ensure_parent_profile(user_id, invite_id),
         {:ok, child} <- find_or_create_child(parent.id, attrs),
         :ok <- publish_family_ready(invite_id, user_id, child.id, parent.id, program_id) do
      {:ok, %{parent: parent, child: child}}
    else
      {:error, reason} ->
        Logger.error("[ProcessInviteClaim] Failed",
          invite_id: invite_id,
          user_id: user_id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  # Trigger: user may already have a parent profile from a prior invite or registration
  # Why: idempotent -- create if missing, fetch if exists
  # Outcome: always returns {:ok, parent} or propagates unexpected error
  defp ensure_parent_profile(user_id, _invite_id) do
    attrs = %{id: Ecto.UUID.generate(), identity_id: user_id}

    with {:ok, _validated} <- ParentProfile.new(attrs),
         {:ok, parent} <- @parent_repository.create_parent_profile(attrs) do
      {:ok, parent}
    else
      {:error, :duplicate_resource} ->
        @parent_query.get_by_identity_id(user_id)

      result ->
        CommandResult.wrap_validation_errors(result)
    end
  end

  # Trigger: invite payload contains child data mapped to domain fields
  # Why: same child may be enrolled in multiple programs -- avoid duplicates
  # Outcome: child found (idempotent) or created and linked to parent
  defp find_or_create_child(parent_id, attrs) do
    invite_id = Map.get(attrs, :invite_id)
    user_id = Map.get(attrs, :user_id)
    first_name = Map.get(attrs, :child_first_name)
    last_name = Map.get(attrs, :child_last_name)
    date_of_birth = Map.get(attrs, :child_date_of_birth)

    # Trigger: event may replay after a crash or redelivery
    # Why: children table has no uniqueness constraint; unconditional create produces duplicates
    # Outcome: find existing child by (first_name, last_name, date_of_birth) for this parent.
    #   Safety relies on the family queue's concurrency-1 guarantee -- without serialized
    #   execution, this find-then-create would be vulnerable to a TOCTOU race condition.
    case find_existing_child(parent_id, first_name, last_name, date_of_birth) do
      %{} = child ->
        Logger.info("[ProcessInviteClaim] Child already exists, skipping creation",
          invite_id: invite_id,
          child_id: child.id,
          parent_id: parent_id
        )

        {:ok, child}

      nil ->
        create_child(parent_id, attrs, invite_id, user_id, first_name, last_name, date_of_birth)
    end
  end

  defp create_child(parent_id, attrs, _invite_id, _user_id, first_name, last_name, date_of_birth) do
    child_attrs = %{
      id: Ecto.UUID.generate(),
      first_name: first_name,
      last_name: last_name,
      date_of_birth: date_of_birth,
      school_grade: Map.get(attrs, :school_grade),
      school_name: Map.get(attrs, :school_name),
      support_needs: Map.get(attrs, :medical_conditions),
      allergies: map_nut_allergy(Map.get(attrs, :nut_allergy, false))
    }

    with {:ok, _validated} <- Child.new(child_attrs),
         {:ok, persisted} <- @child_repository.create_with_guardian(child_attrs, parent_id) do
      {:ok, persisted}
    else
      result -> CommandResult.wrap_validation_errors(result)
    end
  end

  # Trigger: any nil identity field means we cannot reliably match
  # Why: nil == nil is true in Elixir, which would false-match unrelated children
  # Outcome: skip dedup and let domain validation catch the missing field downstream
  defp find_existing_child(_parent_id, nil, _last, _dob), do: nil
  defp find_existing_child(_parent_id, _first, nil, _dob), do: nil
  defp find_existing_child(_parent_id, _first, _last, nil), do: nil

  # Trigger: need to check for duplicate child before creating
  # Why: case-insensitive match aligns with the remediation script's lower() grouping
  # Outcome: returns matching child or nil
  defp find_existing_child(parent_id, first_name, last_name, date_of_birth) do
    parent_id
    |> @child_query.list_by_guardian()
    |> Enum.find(fn child ->
      String.downcase(child.first_name) == String.downcase(first_name) &&
        String.downcase(child.last_name) == String.downcase(last_name) &&
        child.date_of_birth == date_of_birth
    end)
  end

  # Trigger: nut_allergy boolean from invite needs to become a human-readable string
  # Why: Child.allergies is a free-text string field, not a boolean
  # Outcome: true -> "Nut allergy", false/nil -> nil
  defp map_nut_allergy(true), do: "Nut allergy"
  defp map_nut_allergy(_), do: nil

  defp publish_family_ready(invite_id, user_id, child_id, parent_id, program_id) do
    FamilyEvents.invite_family_ready(invite_id, %{
      invite_id: invite_id,
      user_id: user_id,
      child_id: child_id,
      parent_id: parent_id,
      program_id: program_id
    })
    |> EventDispatchHelper.dispatch_or_error(KlassHero.Family)
  end
end
