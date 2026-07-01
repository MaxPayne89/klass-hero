defmodule KlassHero.Enrollment.Application.Commands.CreateEnrollment do
  @moduledoc """
  Use case for creating a new enrollment.

  This use case orchestrates:
  1. Validation of parent profile existence
  2. Validation of booking entitlement (tier-based limits)
  3. Validation of participant eligibility (age, gender, grade restrictions)
  4. Persistence via the repository port

  ## Required Parameters

  - identity_id: The user's identity ID (for validation) OR parent_id (direct)
  - program_id: UUID of the program to enroll in
  - child_id: UUID of the child being enrolled

  ## Optional Parameters

  - status: Enrollment status (defaults to :pending)
  - enrolled_at: DateTime of enrollment (defaults to now)
  - subtotal, vat_amount, card_fee_amount, total_amount: Fee amounts
  - payment_method: "card" or "transfer"
  - special_requirements: Special needs or requirements text

  ## Validation

  When `identity_id` is provided, the use case validates:
  - Parent profile exists for the identity
  - Parent has remaining booking capacity based on their tier
  - Child meets the program's participant restrictions

  When only `parent_id` is provided (direct calls), validation is skipped.
  """

  alias KlassHero.Enrollment
  alias KlassHero.Enrollment.Domain.Events.EnrollmentEvents
  alias KlassHero.Enrollment.Domain.Models.Enrollment, as: EnrollmentModel
  alias KlassHero.Family
  alias KlassHero.Shared.Entitlements
  alias KlassHero.Shared.EventDispatchHelper

  require Logger

  @context KlassHero.Enrollment

  @enrollment_repository Application.compile_env!(:klass_hero, [
                           :enrollment,
                           :for_managing_enrollments
                         ])

  @doc """
  Creates a new enrollment.

  Returns:
  - `{:ok, Enrollment.t()}` on success
  - `{:error, :no_parent_profile}` if no parent profile exists for identity
  - `{:error, :booking_limit_exceeded}` if monthly booking cap reached
  - `{:error, :ineligible, [String.t()]}` if child fails participant restrictions
  - `{:error, :processing_failed}` if eligibility check fails unexpectedly
  - `{:error, :duplicate_resource}` if active enrollment exists for child/program
  - `{:error, term()}` on validation or persistence failure
  """
  @spec execute(map()) ::
          {:ok, EnrollmentModel.t()} | {:error, :ineligible, [String.t()]} | {:error, term()}
  def execute(%{identity_id: identity_id} = params) when is_binary(identity_id) do
    with {:ok, parent} <- fetch_parent(identity_id),
         {:ok, _parent} <-
           Entitlements.ensure_booking_capacity(
             parent,
             Enrollment.count_monthly_bookings(parent.id)
           ),
         {:ok, :eligible} <- ensure_eligible(params[:program_id], params[:child_id]) do
      params
      |> build_enrollment_attrs(parent.id)
      |> persist_and_dispatch(identity_id)
    end
  end

  def execute(params) when is_map(params) do
    params
    |> build_enrollment_attrs(params[:parent_id])
    |> persist_and_dispatch(params[:identity_id])
  end

  defp fetch_parent(identity_id) do
    case Family.get_parent_by_identity(identity_id) do
      {:ok, parent} -> {:ok, parent}
      {:error, :not_found} -> {:error, :no_parent_profile}
    end
  end

  # 3-tuple {:error, :ineligible, reasons} bubbles verbatim; 2-tuple lookup failures map to
  # :processing_failed (fail-closed when eligibility cannot be verified).
  defp ensure_eligible(program_id, child_id) do
    case Enrollment.check_participant_eligibility(program_id, child_id) do
      {:ok, :eligible} ->
        {:ok, :eligible}

      {:error, :ineligible, reasons} ->
        {:error, :ineligible, reasons}

      {:error, reason} ->
        Logger.warning("[Enrollment.CreateEnrollment] Eligibility check failed unexpectedly",
          program_id: program_id,
          child_id: child_id,
          reason: inspect(reason)
        )

        {:error, :processing_failed}
    end
  end

  defp build_enrollment_attrs(params, parent_id) do
    %{
      program_id: params[:program_id],
      child_id: params[:child_id],
      parent_id: parent_id,
      status: params[:status] || :pending,
      enrolled_at: params[:enrolled_at] || DateTime.utc_now(),
      subtotal: params[:subtotal],
      vat_amount: params[:vat_amount],
      card_fee_amount: params[:card_fee_amount],
      total_amount: params[:total_amount],
      payment_method: params[:payment_method],
      special_requirements: params[:special_requirements]
    }
  end

  defp persist_and_dispatch(attrs, identity_id) do
    case @enrollment_repository.create_with_capacity_check(attrs, attrs[:program_id]) do
      {:ok, enrollment} ->
        dispatch_enrollment_created(enrollment, identity_id)
        {:ok, enrollment}

      error ->
        error
    end
  end

  # Fire-and-forget — a failed handler must not roll back a successful enrollment.
  defp dispatch_enrollment_created(enrollment, identity_id) do
    EnrollmentEvents.enrollment_created(enrollment.id, %{
      enrollment_id: enrollment.id,
      child_id: enrollment.child_id,
      parent_id: enrollment.parent_id,
      parent_user_id: identity_id,
      program_id: enrollment.program_id,
      status: enrollment.status
    })
    |> EventDispatchHelper.dispatch(@context)
  end
end
