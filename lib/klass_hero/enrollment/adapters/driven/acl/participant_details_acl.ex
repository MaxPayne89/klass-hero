defmodule KlassHero.Enrollment.Adapters.Driven.ACL.ParticipantDetailsACL do
  @moduledoc """
  ACL adapter that translates Family context child data into
  Enrollment's participant details representation.

  The Enrollment context never directly depends on Family domain models.
  This adapter queries the Family facade and maps only the fields
  needed for eligibility checks into a plain map.
  """

  use KlassHero.Shared.Tracing

  alias KlassHero.Family

  def get_participant_details(child_id) do
    acl_span source: "enrollment", target: "family" do
      case Family.get_child_by_id(child_id) do
        {:ok, child} ->
          {:ok,
           %{
             date_of_birth: child.date_of_birth,
             gender: child.gender,
             school_grade: child.school_grade
           }}

        {:error, :not_found} ->
          {:error, :not_found}
      end
    end
  end
end
