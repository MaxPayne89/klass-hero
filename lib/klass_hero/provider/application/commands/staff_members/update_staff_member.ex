defmodule KlassHero.Provider.Application.Commands.StaffMembers.UpdateStaffMember do
  @moduledoc """
  Use case for updating an existing staff member.

  Loads the staff member, merges updated fields, validates, then persists.
  """

  alias KlassHero.Provider.Domain.Models.StaffMember
  alias KlassHero.Shared.CommandResult

  @query Application.compile_env!(:klass_hero, [:provider, :for_querying_staff_members])
  @repository Application.compile_env!(:klass_hero, [:provider, :for_storing_staff_members])

  @allowed_fields ~w(first_name last_name role email bio headshot_url tags qualifications active pay_rate)a

  def execute(staff_id, attrs) when is_binary(staff_id) and is_map(attrs) do
    attrs = Map.take(attrs, @allowed_fields)

    with {:ok, existing} <- @query.get(staff_id),
         merged = Map.merge(Map.from_struct(existing), attrs),
         {:ok, _validated} <- StaffMember.new(merged),
         # Update the existing struct (not the validated one) to preserve timestamps.
         updated = struct(existing, attrs),
         {:ok, persisted} <- @repository.update(updated) do
      {:ok, persisted}
    else
      result -> CommandResult.wrap_validation_errors(result)
    end
  end
end
