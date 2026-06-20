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

  require Logger

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
    case resolve_outcome(iv, outcome) do
      :ignore ->
        {:ok, :ignored}

      {updated, event_type} ->
        with {:ok, persisted} <- @store.update(updated) do
          dispatch(event_type, persisted)
          {:ok, persisted}
        end
    end
  end

  # Maps the normalised Stripe outcome to the IdentityVerification transition and the domain event
  # to emit, returning `{updated_identity_verification, event_type}` — or `:ignore` to make the
  # command a no-op (handled fail-closed by `apply_and_dispatch`).
  #
  # A Stripe `:verified` status is NOT automatically a pass — the age gate can still fail it, so we
  # inspect the resulting record's `outcome` (`:pass` / `:fail`). `:requires_input` and `:canceled`
  # are always failures.
  defp resolve_outcome(%IdentityVerification{} = iv, %{stripe_status: :verified, dob: dob, today: today}) do
    updated = IdentityVerification.mark_verified(iv, dob, today)
    {updated, event_for(updated.outcome)}
  end

  defp resolve_outcome(%IdentityVerification{} = iv, %{stripe_status: :requires_input}) do
    updated = IdentityVerification.mark_requires_input(iv)
    {updated, event_for(updated.outcome)}
  end

  defp resolve_outcome(%IdentityVerification{} = iv, %{stripe_status: :canceled}) do
    updated = IdentityVerification.mark_canceled(iv)
    {updated, event_for(updated.outcome)}
  end

  # Fail-closed catch-all: an unmapped Stripe status must never fabricate a pass/fail. Log it loudly
  # and no-op (`:ignore`), leaving the record untouched until the status is taught to the system.
  defp resolve_outcome(%IdentityVerification{} = _iv, %{stripe_status: stripe_status}) do
    Logger.warning("Ignoring unmapped Stripe identity status: #{inspect(stripe_status)}")
    :ignore
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
