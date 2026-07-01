defmodule KlassHero.Enrollment.Adapters.Driving.Events.EventHandlers.EnqueueInviteEmails do
  @moduledoc """
  Event handler adapter that delegates to the EnqueueInviteEmails use case
  and maps the result into Oban jobs.

  Triggered by `:bulk_invites_imported` on the Enrollment DomainEventBus.
  """

  alias KlassHero.Enrollment.Adapters.Driving.Workers.SendInviteEmailWorker
  alias KlassHero.Enrollment.EnqueueInviteEmails, as: UseCase
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.Tracing.Context

  require Logger

  @spec handle(DomainEvent.t()) :: :ok
  def handle(%DomainEvent{event_type: :bulk_invites_imported} = event) do
    %{provider_id: provider_id, program_ids: program_ids, count: count} = event.payload

    Logger.info("[EnqueueInviteEmails] Processing bulk import event",
      provider_id: provider_id,
      program_count: length(program_ids),
      count: count
    )

    {:ok, pairs} = UseCase.execute(program_ids, provider_id)

    if pairs != [] do
      jobs =
        Enum.map(pairs, fn {invite_id, program_name} ->
          args = Context.inject_into_args(%{invite_id: invite_id, program_name: program_name})
          SendInviteEmailWorker.new(args)
        end)

      Oban.insert_all(jobs)

      Logger.info("[EnqueueInviteEmails] Enqueued invite emails", count: length(jobs))
    end

    :ok
  end

  @spec handle(DomainEvent.t()) :: :ok
  def handle(%DomainEvent{event_type: :invite_resend_requested} = event) do
    %{provider_id: provider_id, invite_id: invite_id, program_id: program_id} = event.payload

    Logger.info("[EnqueueInviteEmails] Processing resend request",
      provider_id: provider_id,
      invite_id: invite_id,
      program_id: program_id
    )

    {:ok, pairs} = UseCase.execute([program_id], provider_id)

    # UseCase assigns tokens for ALL pending invites in the program (correct), but only
    # the requested invite should get an immediate Oban job — other pending invites wait.
    pairs_for_invite = Enum.filter(pairs, fn {id, _name} -> id == invite_id end)

    if pairs_for_invite != [] do
      jobs =
        Enum.map(pairs_for_invite, fn {id, program_name} ->
          args = Context.inject_into_args(%{invite_id: id, program_name: program_name})
          SendInviteEmailWorker.new(args)
        end)

      Oban.insert_all(jobs)

      Logger.info("[EnqueueInviteEmails] Enqueued resend email", count: length(jobs))
    end

    :ok
  end
end
