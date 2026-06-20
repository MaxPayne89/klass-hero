defmodule KlassHero.Provider.Application.Commands.Verification.RecordIdentityVerificationOutcome do
  @moduledoc """
  Records the outcome of a Stripe Identity session (delivered by webhook) against its
  `IdentityVerification` record, applying the fail-closed age gate, and emits a domain event that
  advances the provider's `:identity` vetting step (ADR-0007).

  Idempotent and out-of-order safe: an unknown session id is ignored, and a record already in a
  terminal state is left untouched (a duplicate or late `processing`→terminal event is a no-op).

  Input (normalised by the webhook controller):

      %{
        session_id: String.t(),
        stripe_status: :verified | :requires_input | :canceled,
        dob: %{day: integer, month: integer, year: integer} | nil,  # present only for :verified
        today: Date.t()                                             # reference date for the age gate
      }
  """

  alias KlassHero.Provider.Domain.Models.IdentityVerification
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.EventDispatchHelper

  @query Application.compile_env!(:klass_hero, [:provider, :for_querying_identity_verifications])
  @store Application.compile_env!(:klass_hero, [:provider, :for_storing_identity_verifications])

  @doc """
  Applies the outcome. Returns `{:ok, IdentityVerification.t()}` when a processing record is
  advanced, `{:ok, :ignored}` for an unknown session, or `{:ok, :already_recorded}` when the
  record is already terminal.
  """
  def execute(%{session_id: session_id} = outcome) do
    case @query.get_by_session_id(session_id) do
      {:error, :not_found} -> {:ok, :ignored}
      {:ok, %IdentityVerification{status: :processing} = iv} -> apply_and_dispatch(iv, outcome)
      {:ok, %IdentityVerification{}} -> {:ok, :already_recorded}
    end
  end

  defp apply_and_dispatch(iv, outcome) do
    {updated, event_type} = resolve_outcome(iv, outcome)

    with {:ok, persisted} <- @store.update(updated) do
      dispatch(event_type, persisted)
      {:ok, persisted}
    end
  end

  # TODO(human): map the normalised Stripe outcome to the IdentityVerification transition and the
  # domain event to emit. Return `{updated_identity_verification, event_type}` where `event_type`
  # is `:identity_verification_passed` or `:identity_verification_failed`.
  #
  # The IdentityVerification model already provides the transitions:
  #   - IdentityVerification.mark_verified(iv, dob, today)  # runs the fail-closed age gate
  #   - IdentityVerification.mark_requires_input(iv)
  #   - IdentityVerification.mark_canceled(iv)
  #
  # Decisions to make:
  #   - A Stripe `:verified` status is NOT automatically a pass — the age gate can still fail it.
  #     Inspect the resulting record's `outcome` (`:pass` / `:fail`) to choose the event.
  #   - `:requires_input` and `:canceled` are always failures.
  # `outcome` is the map documented in @moduledoc (stripe_status, dob, today).
  defp resolve_outcome(%IdentityVerification{} = iv, %{stripe_status: :verified, dob: dob, today: today}) do
    updated = IdentityVerification.mark_verified(iv, dob, today)
    {updated, event_for(updated.outcome)}
  end

  defp resolve_outcome(%IdentityVerification{} = iv, %{stripe_status: stripe_status}) do
    updated =
      case stripe_status do
        :requires_input -> IdentityVerification.mark_requires_input(iv)
        :canceled -> IdentityVerification.mark_canceled(iv)
      end

    {updated, event_for(updated.outcome)}
  end

  defp event_for(:pass), do: :identity_verification_passed
  defp event_for(:fail), do: :identity_verification_failed

  defp dispatch(event_type, iv) do
    DomainEvent.new(event_type, iv.id, :identity_verification, %{
      provider_id: iv.provider_id,
      identity_verification_id: iv.id,
      stripe_session_id: iv.stripe_session_id,
      failure_reason: iv.failure_reason
    })
    |> EventDispatchHelper.dispatch(KlassHero.Provider)
  end
end
