defmodule KlassHero.EmailQueueCapacityTest do
  @moduledoc """
  The `:email` queue's concurrency and its workers' retry budget are one
  decision, not two.

  Concurrency was raised from 1 to 5 so a program broadcast's fan-out stops
  head-of-line blocking staff invites and email replies. That makes 429s from
  Resend more likely, not less — the upstream limit did not move. What keeps a
  rate-limited job from being *discarded* instead of merely delayed is the
  retry budget, because `RateLimitedEmailWorker` spends attempts on 429 backoff
  (30s → 60s → 120s …).

  So lowering either half in isolation silently converts "this email is late"
  into "this email is gone". Asserted together, in one test, because checking
  either alone would go green on a broken pair.
  """
  use ExUnit.Case, async: true

  alias KlassHero.Enrollment.Adapters.Driving.Workers.SendInviteEmailWorker
  alias KlassHero.Messaging.Workers.FetchEmailContentWorker
  alias KlassHero.Messaging.Workers.NewMessageEmailWorker
  alias KlassHero.Messaging.Workers.SendEmailReplyWorker
  alias KlassHero.Provider.NotifyIncidentReportedWorker

  @email_workers [
    SendInviteEmailWorker,
    FetchEmailContentWorker,
    NewMessageEmailWorker,
    SendEmailReplyWorker,
    NotifyIncidentReportedWorker
  ]

  test "concurrency above one is paid for by a retry budget that outlasts a 429 burst" do
    concurrency =
      :klass_hero
      |> Application.fetch_env!(Oban)
      |> Keyword.fetch!(:queues)
      |> Keyword.fetch!(:email)

    assert concurrency >= 5,
           "the :email queue is back to #{concurrency} — a broadcast's fan-out will " <>
             "block staff invites and email replies behind it"

    for worker <- @email_workers do
      opts = worker.__opts__()

      assert Keyword.fetch!(opts, :queue) == :email,
             "#{inspect(worker)} is listed here but is not on the :email queue"

      assert Keyword.fetch!(opts, :max_attempts) >= 5,
             "#{inspect(worker)} has too small a retry budget: a sustained 429 burst " <>
               "would exhaust it on backoff alone and discard a real email"
    end
  end
end
