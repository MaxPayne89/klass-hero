defmodule KlassHero.Provider.Application.Commands.StaffMembers.SelectStaffContext do
  @moduledoc """
  Use case for a multi-employer staff user picking which employment their
  staff scope represents (#969 staff-context switcher).

  Bumps `last_selected_at` on the user's active staff row at the given
  provider; scope resolution (`get_active_by_user/1`) orders by that
  timestamp, so the selection takes effect on the next mount. The selection
  is remembered across sessions and devices.
  """

  @repository Application.compile_env!(:klass_hero, [:provider, :for_storing_staff_members])

  @doc """
  Marks the user's employment at `provider_id` as the currently selected
  staff context.

  Returns `{:error, :not_staffed}` when the user has no active staff row at
  that provider — the single authorization gate for switching.
  """
  @spec execute(String.t(), String.t()) :: {:ok, :selected} | {:error, :not_staffed}
  def execute(user_id, provider_id) when is_binary(user_id) and is_binary(provider_id) do
    @repository.touch_last_selected(user_id, provider_id)
  end
end
