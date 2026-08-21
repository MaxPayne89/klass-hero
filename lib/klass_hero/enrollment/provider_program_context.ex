defmodule KlassHero.Enrollment.ProviderProgramContext do
  @moduledoc """
  Builds the shared `programs_by_title` lookup context that invite-creation
  commands use to resolve a human-readable program name into a `program_id`.

  Shared by `ImportEnrollmentCsv` (CSV path) and `InviteSingleParticipant`
  (manual form). Centralising the title-collision check here guarantees both
  commands reject the same ambiguous catalog state.

  Returned map uses downcased keys for case-insensitive lookup downstream.
  """

  alias KlassHero.Enrollment.Adapters.Driven.ACL.ProgramCatalogACL

  @type context :: %{
          provider_id: binary(),
          programs_by_title: %{String.t() => binary()}
        }

  @spec for_provider(binary()) ::
          {:ok, context()}
          | {:error, :no_programs}
          | {:error, {:title_collisions, [String.t()]}}
  def for_provider(provider_id) when is_binary(provider_id) do
    programs_by_title = ProgramCatalogACL.list_program_titles_for_provider(provider_id)

    if programs_by_title == %{} do
      {:error, :no_programs}
    else
      with {:ok, downcased} <- check_title_collisions(programs_by_title) do
        {:ok, %{provider_id: provider_id, programs_by_title: downcased}}
      end
    end
  end

  # Titles differing only by case (e.g. "Yoga" vs "YOGA") would silently collapse to the same key after downcasing.
  defp check_title_collisions(programs_by_title) do
    collisions =
      programs_by_title
      |> Map.keys()
      |> Enum.group_by(&String.downcase/1)
      |> Enum.filter(fn {_downcased, titles} -> match?([_, _ | _], titles) end)

    if collisions == [] do
      downcased =
        Map.new(programs_by_title, fn {title, id} -> {String.downcase(title), id} end)

      {:ok, downcased}
    else
      conflicting = Enum.flat_map(collisions, fn {_downcased, titles} -> titles end)
      {:error, {:title_collisions, conflicting}}
    end
  end
end
