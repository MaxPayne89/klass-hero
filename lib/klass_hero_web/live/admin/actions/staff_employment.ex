defmodule KlassHeroWeb.Admin.Actions.StaffEmployment do
  @moduledoc """
  Shared execution for the admin's staff employment item actions.

  `DeactivateStaffAction` and `ActivateStaffAction` differ only in which domain
  command they run and what the flash says, so the apply-and-summarise loop lives
  here rather than twice.

  Both go through `KlassHero.Provider`'s public API instead of Backpex's direct
  `Repo` write. That is the whole point of #1237: the admin toggle used to cast
  `active` with no consequences attached, so a deactivated staff member kept
  their lead-instructor flag and stayed named in read tables.
  """

  alias KlassHero.Provider.StaffMember
  alias Phoenix.LiveView.Socket

  require Logger

  @doc """
  Runs `command` over each selected staff member and puts a summarising flash.

  `copy` supplies the verbs: `:done` for the success flash ("deactivated"),
  `:failed` for the failure one, and `:log` for the warning label.
  """
  @spec apply_to(Socket.t(), [StaffMember.t()], (StaffMember.t() -> {:ok, term()} | {:error, term()}), keyword()) ::
          {:ok, Socket.t()}
  def apply_to(socket, items, command, copy) do
    results = Enum.map(items, fn item -> {item.id, command.(item)} end)
    failures = Enum.reject(results, fn {_id, result} -> match?({:ok, _}, result) end)

    Enum.each(failures, fn {id, error} ->
      Logger.warning("[Admin.#{copy[:log]}] Failed to update staff employment",
        staff_member_id: id,
        error: inspect(error)
      )
    end)

    {:ok, Phoenix.LiveView.put_flash(socket, level(failures, items), message(failures, items, copy))}
  end

  defp level([], _items), do: :info
  defp level(failures, items) when length(failures) == length(items), do: :error
  defp level(_failures, _items), do: :warning

  defp message([], items, copy), do: "#{length(items)} staff member(s) #{copy[:done]}."

  defp message(failures, items, copy) when length(failures) == length(items) do
    "Could not #{copy[:failed]} #{length(items)} staff member(s)."
  end

  defp message(failures, items, copy) do
    ok_count = length(items) - length(failures)

    "#{ok_count} of #{length(items)} staff member(s) #{copy[:done]}. " <>
      "#{length(failures)} could not be #{copy[:done]}."
  end
end
