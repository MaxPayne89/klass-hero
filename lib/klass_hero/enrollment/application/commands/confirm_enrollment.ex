defmodule KlassHero.Enrollment.Application.Commands.ConfirmEnrollment do
  @moduledoc """
  Confirms a pending enrollment when approved by the owning provider.

  Pipeline:
    1. Fetch the enrollment.
    2. Verify the provider owns the program (ProgramCatalog ACL).
    3. Apply the domain `pending → confirmed` transition.
    4. Persist the new status + confirmed_at timestamp.
    5. Dispatch an `:enrollment_confirmed` domain event.
  """

  alias KlassHero.Enrollment.Domain.Events.EnrollmentEvents
  alias KlassHero.Enrollment.Domain.Models.Enrollment
  alias KlassHero.Shared.EventDispatchHelper

  require Logger

  @context KlassHero.Enrollment

  @enrollment_reader Application.compile_env!(:klass_hero, [
                       :enrollment,
                       :for_querying_enrollments
                     ])
  @enrollment_repo Application.compile_env!(:klass_hero, [
                     :enrollment,
                     :for_managing_enrollments
                   ])
  @program_catalog Application.compile_env!(:klass_hero, [
                     :enrollment,
                     :for_resolving_program_catalog
                   ])

  @doc """
  Confirms a pending enrollment.

  ## Parameters

  - `:enrollment_id` — UUID of the enrollment
  - `:provider_id` — UUID of the provider attempting to approve

  ## Returns

  - `{:ok, Enrollment.t()}` — confirmation succeeded
  - `{:error, :not_found}` — enrollment does not exist
  - `{:error, :unauthorized}` — provider does not own the program
  - `{:error, :invalid_status_transition}` — enrollment is not pending
  - `{:error, term()}` — persistence failure
  """
  @spec execute(%{enrollment_id: String.t(), provider_id: String.t()}) ::
          {:ok, Enrollment.t()}
          | {:error, :not_found | :unauthorized | :invalid_status_transition | term()}
  def execute(%{enrollment_id: enrollment_id, provider_id: provider_id})
      when is_binary(enrollment_id) and is_binary(provider_id) do
    with {:ok, enrollment_id} <- cast_uuid_or_not_found(enrollment_id),
         {:ok, enrollment} <- @enrollment_reader.get_by_id(enrollment_id),
         :ok <- authorize(enrollment, provider_id),
         {:ok, confirmed} <- Enrollment.confirm(enrollment),
         {:ok, persisted} <- @enrollment_repo.update(enrollment_id, to_update_attrs(confirmed)),
         {:ok, persisted} <- dispatch_event(persisted, provider_id) do
      Logger.info("[Enrollment.ConfirmEnrollment] Enrollment confirmed",
        enrollment_id: enrollment_id,
        provider_id: provider_id
      )

      {:ok, persisted}
    end
  end

  # `enrollment_id` arrives from the LiveView `phx-value-id` (DOM-tamperable). Without this
  # guard, `Repo.get/2` raises `Ecto.Query.CastError` on malformed input. `provider_id` is
  # server-trusted (read from `current_scope`), so only the enrollment id needs guarding;
  # any invalid `provider_id` is already handled by `ProgramCatalogACL.program_owned_by?/2`
  # returning false, which translates to `{:error, :unauthorized}`.
  defp cast_uuid_or_not_found(id) do
    case Ecto.UUID.cast(id) do
      {:ok, _} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end

  defp authorize(%Enrollment{program_id: program_id}, provider_id) do
    if @program_catalog.program_owned_by?(program_id, provider_id) do
      :ok
    else
      {:error, :unauthorized}
    end
  end

  defp to_update_attrs(%Enrollment{} = enrollment) do
    %{status: enrollment.status, confirmed_at: enrollment.confirmed_at}
  end

  defp dispatch_event(%Enrollment{} = persisted, provider_id) do
    # Publish the canonical enrollment:enrollment_confirmed domain event to PubSub.
    # The generic NotifyLiveViews handler derives the topic as "enrollment:enrollment_confirmed",
    # which is not provider-scoped. We also broadcast a provider-scoped notification so that
    # the provider DashboardLive can subscribe to their own topic and refresh the pending list
    # without receiving events from other providers.
    dispatch_result =
      persisted.id
      |> EnrollmentEvents.enrollment_confirmed(%{
        enrollment_id: persisted.id,
        program_id: persisted.program_id,
        child_id: persisted.child_id,
        parent_id: persisted.parent_id,
        confirmed_at: persisted.confirmed_at
      })
      |> EventDispatchHelper.dispatch_or_error(@context)

    # Supplementary provider-scoped broadcast — best-effort (mirrors PubSub best-effort policy).
    Phoenix.PubSub.broadcast(
      KlassHero.PubSub,
      "enrollment:provider:#{provider_id}:pending_changed",
      :enrollment_pending_changed
    )

    case dispatch_result do
      :ok -> {:ok, persisted}
      {:error, _} = err -> err
    end
  end
end
