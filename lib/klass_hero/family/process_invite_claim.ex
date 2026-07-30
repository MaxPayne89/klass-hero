defmodule KlassHero.Family.ProcessInviteClaim do
  @moduledoc """
  Use case for processing an invite claim into a family unit.

  Orchestrates: ensure parent profile, find-or-create child, publish
  `invite_family_ready` event. Called by the Oban worker, which serializes
  execution via a single-concurrency queue to prevent duplicate children.
  """

  alias KlassHero.Family
  alias KlassHero.Family.Domain.Events.FamilyEvents
  alias KlassHero.Shared.Outbox

  require Logger

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

    # One transaction: the parent, the child, and the event saying the family is ready
    # commit together. Oban retries stay safe because ensure_parent_profile and
    # find_or_create_child are idempotent — they find existing records rather than
    # duplicating them.
    result =
      Outbox.transact(KlassHero.Family, fn ->
        with {:ok, parent} <- ensure_parent_profile(user_id, invite_id),
             {:ok, child} <- find_or_create_child(parent.id, attrs) do
          event = family_ready_event(invite_id, user_id, child.id, parent.id, program_id)
          {:ok, %{parent: parent, child: child}, [event]}
        end
      end)

    case result do
      {:ok, {family, _events}} ->
        {:ok, family}

      {:error, reason} ->
        Logger.error("[ProcessInviteClaim] Failed",
          invite_id: invite_id,
          user_id: user_id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  # Idempotent: creates parent profile if missing, fetches if already exists.
  defp ensure_parent_profile(user_id, _invite_id) do
    case Family.create_parent_profile(%{identity_id: user_id}) do
      {:ok, parent} -> {:ok, parent}
      {:error, :duplicate_resource} -> Family.get_parent_by_identity(user_id)
      {:error, reason} -> {:error, reason}
    end
  end

  # Same child may be enrolled in multiple programs — find-or-create to avoid duplicates.
  defp find_or_create_child(parent_id, attrs) do
    invite_id = Map.get(attrs, :invite_id)
    user_id = Map.get(attrs, :user_id)
    first_name = Map.get(attrs, :child_first_name)
    last_name = Map.get(attrs, :child_last_name)
    date_of_birth = Map.get(attrs, :child_date_of_birth)

    # children table has no uniqueness constraint; match by name+dob to avoid duplicates on replay.
    # TOCTOU safety relies on the family queue's concurrency-1 guarantee.
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
    Family.create_child(%{
      parent_id: parent_id,
      first_name: first_name,
      last_name: last_name,
      date_of_birth: date_of_birth,
      school_grade: Map.get(attrs, :school_grade),
      school_name: Map.get(attrs, :school_name),
      support_needs: Map.get(attrs, :medical_conditions),
      allergies: map_nut_allergy(Map.get(attrs, :nut_allergy, false))
    })
  end

  # nil == nil is true in Elixir, so nil fields would false-match unrelated children; skip dedup.
  defp find_existing_child(_parent_id, nil, _last, _dob), do: nil
  defp find_existing_child(_parent_id, _first, nil, _dob), do: nil
  defp find_existing_child(_parent_id, _first, _last, nil), do: nil

  # Case-insensitive match aligns with the remediation script's lower() grouping.
  defp find_existing_child(parent_id, first_name, last_name, date_of_birth) do
    parent_id
    |> Family.get_children()
    |> Enum.find(fn child ->
      String.downcase(child.first_name) == String.downcase(first_name) &&
        String.downcase(child.last_name) == String.downcase(last_name) &&
        child.date_of_birth == date_of_birth
    end)
  end

  # Child.allergies is free-text; map invite boolean to a string value.
  defp map_nut_allergy(true), do: "Nut allergy"
  defp map_nut_allergy(_), do: nil

  defp family_ready_event(invite_id, user_id, child_id, parent_id, program_id) do
    FamilyEvents.invite_family_ready(invite_id, %{
      invite_id: invite_id,
      user_id: user_id,
      child_id: child_id,
      parent_id: parent_id,
      program_id: program_id
    })
  end
end
