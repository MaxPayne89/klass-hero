defmodule KlassHeroWeb.Journeys do
  @moduledoc """
  Arrange- and act-helpers shared by the flow tests under `test/flows/`.

  Two rules this module exists to enforce, both from ADR-0020:

  1. **Arrange through the facade, never the read table.** A flow test that seeds
     `program_listings` directly can never prove a program reached the catalog —
     which is exactly the property the tier is there for. `published_program/1`
     goes through `ProgramCatalog.create_program/1` and lets the real delivery
     chain write the read table.

  2. **Cross-CQRS acts run under the real outbox.** `config/test.exs` points
     `:outbox` at `TestOutbox`, which records staged events in the process
     dictionary and delivers nothing. `with_real_outbox/1` swaps in `ObanOutbox`
     for the duration of one act and drains, so the consumers registered under
     `:event_consumers` actually run.
  """

  use KlassHeroWeb, :verified_routes

  import KlassHero.Factory
  import Phoenix.ConnTest

  alias KlassHero.Enrollment
  alias KlassHero.Enrollment.BulkEnrollmentInvite
  alias KlassHero.ProgramCatalog
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Events.ObanOutbox

  @endpoint KlassHeroWeb.Endpoint

  # A saga crosses queues: `invite_claimed` is delivered on :events, the family hop
  # it enqueues runs on :family, and the `invite_family_ready` that hop stages goes
  # back onto :events. Draining one queue once truncates the chain silently, which is
  # the same class of bug this tier exists to catch — so drain every configured queue
  # in a loop until a whole pass does no work.
  @max_drain_passes 6

  @doc """
  Runs `fun` with the real `ObanOutbox` staged and delivers everything it sets off.

  Manual testing mode rather than the suite's `testing: :inline` is what makes this
  resemble production: inline executes the delivery job at insert, inside the
  producer's own transaction, so consumers would run before the write they describe
  had committed.

  The swap stays in place across the drains. Restoring it first — the shape the
  eight hand-rolled copies of this recipe use — sends anything a *consumer* stages
  into `TestOutbox`, so a multi-hop saga stops after its first hop.

  Because the swap is a global `Application.put_env`, every module using this must
  be `async: false`; `KlassHeroWeb.FlowCase` enforces that.
  """
  def with_real_outbox(fun) when is_function(fun, 0) do
    original = Application.get_env(:klass_hero, :outbox)
    Application.put_env(:klass_hero, :outbox, module: ObanOutbox)

    try do
      # Settle first, then act, then settle again. Without the leading drain, a job
      # left pending by an earlier act is delivered by *this* act's drain — i.e.
      # after it — and replays its event out of order. That is how a `messages_read`
      # staged by a previous page visit came to re-zero an unread count that the
      # message just sent had correctly incremented.
      drain_until_settled(@max_drain_passes)
      result = Oban.Testing.with_testing_mode(:manual, fun)
      drain_until_settled(@max_drain_passes)
      result
    after
      Application.put_env(:klass_hero, :outbox, original)
    end
  end

  defp drain_until_settled(0), do: :ok

  defp drain_until_settled(passes) do
    executed =
      for {queue, _limit} <- Application.get_env(:klass_hero, Oban)[:queues], reduce: 0 do
        acc ->
          result = Oban.drain_queue(queue: queue, with_recursion: true)
          acc + result.success + result.failure + result.discard
      end

    if executed > 0, do: drain_until_settled(passes - 1), else: :ok
  end

  @doc """
  Creates a program through `ProgramCatalog.create_program/1` and delivers its
  `program_created` event.

  Both the `programs` write table (read by `ProgramDetailLive` and `BookingLive`)
  and the `program_listings` read table (read by the public `ProgramsLive`) are
  current on return, because `{ProgramListings, :project}` ran for real.

  Pass `:provider` to reuse an existing provider profile; anything else is merged
  into the create attrs.
  """
  def published_program(attrs \\ %{}) do
    provider = attrs[:provider] || insert(:provider_profile_schema)

    create_attrs =
      Map.merge(
        %{
          provider_id: provider.id,
          title: "Soccer Stars",
          description: "Learn soccer fundamentals and teamwork",
          category: "sports",
          age_range: "6-12 years",
          price: Decimal.new("100.00"),
          pricing_period: "per month",
          meeting_days: ["Monday", "Wednesday"],
          meeting_start_time: ~T[15:00:00],
          meeting_end_time: ~T[17:00:00]
        },
        Map.delete(attrs, :provider)
      )

    {:ok, program} = with_real_outbox(fn -> ProgramCatalog.create_program(create_attrs) end)

    program
  end

  @doc """
  Creates a `BulkEnrollmentInvite` in the `:invite_sent` state with a usable token.

  Production assigns the token in bulk from `EnqueueInviteEmails`, off the
  `invite_family_ready` event. Stamping it here keeps the arrange to one step and
  matches what `invite_claim_controller_test.exs` already does.

  Returns `%{invite: invite, token: token, email: guardian_email, program: program}`.
  """
  def sent_invite(overrides \\ %{}) do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)
    token = "flow-invite-#{System.unique_integer([:positive])}"
    email = "flow-guardian-#{System.unique_integer([:positive])}@example.com"

    attrs =
      Map.merge(
        %{
          program_id: program.id,
          provider_id: provider.id,
          child_first_name: "Emma",
          child_last_name: "Schmidt",
          child_date_of_birth: ~D[2016-03-15],
          guardian_email: email,
          guardian_first_name: "Anna",
          guardian_last_name: "Schmidt"
        },
        overrides
      )

    {:ok, _} = Enrollment.create_invite(attrs)

    invite =
      BulkEnrollmentInvite
      |> Repo.get_by!(guardian_email: attrs.guardian_email)
      |> Ecto.Changeset.change(%{invite_token: token, status: :invite_sent})
      |> Repo.update!()

    %{invite: invite, token: token, email: attrs.guardian_email, program: program}
  end

  @doc """
  Completes the magic-link login that `conn` was just redirected into.

  `conn` must be the result of a request that redirected to `/users/log-in/:token`.
  Returns a logged-in `conn`, ready to hand to `PhoenixTest.visit/2`.

  This posts to `UserSessionController` rather than driving `UserLive.Confirmation`'s
  form, because that LiveView renders **two** `phx-trigger-action` forms (mobile and
  desktop) and `phoenix_test` raises `"Found multiple forms with phx-trigger-action."`
  on more than one. The real session write and `signed_in_path/1` redirect still run;
  only the duplicated client-side trigger is skipped, and that is browser-tier work
  (ADR-0020).
  """
  def follow_magic_link(conn) do
    magic_token =
      conn
      |> redirected_to()
      |> String.split("/")
      |> List.last()

    conn
    |> recycle()
    |> post(~p"/users/log-in?_action=confirmed", %{"user" => %{"token" => magic_token}})
  end
end
