defmodule KlassHero.Messaging.Adapters.Driven.Enrollment.EnrollmentResolver do
  @moduledoc """
  Adapter for querying enrollment data from the Enrollment bounded context.

  Delegates to the Enrollment facade instead of querying Enrollment/Identity
  schemas directly, respecting bounded context boundaries.
  """

  @behaviour KlassHero.Messaging.Domain.Ports.ForQueryingEnrollments

  use KlassHero.Shared.Tracing

  @impl true
  @spec get_enrolled_parent_user_ids(String.t()) :: [String.t()]
  def get_enrolled_parent_user_ids(program_id) do
    acl_span source: "messaging", target: "enrollment" do
      KlassHero.Enrollment.list_enrolled_identity_ids(program_id)
    end
  end

  @impl true
  @spec is_enrolled?(String.t(), String.t()) :: boolean()
  def is_enrolled?(program_id, parent_user_id) do
    acl_span source: "messaging", target: "enrollment" do
      KlassHero.Enrollment.enrolled?(program_id, parent_user_id)
    end
  end
end
