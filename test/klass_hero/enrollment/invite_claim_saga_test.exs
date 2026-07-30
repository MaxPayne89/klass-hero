defmodule KlassHero.Enrollment.InviteClaimSagaTest do
  @moduledoc """
  Integration test for the full invite claim saga.

  Verifies the end-to-end flow: token claim -> user creation ->
  invite_claimed event -> registered status transition ->
  integration event -> family creation -> enrollment creation.

  Since integration events propagate asynchronously via PubSub
  (through EventSubscriber GenServers started in the application tree),
  this test:

  1. Swaps the integration event publisher to the real PubSub publisher
     so that PromoteIntegrationEvents handlers actually broadcast events
  2. Grants Ecto Sandbox access to the EventSubscriber processes so they
     can access the database within the test's transaction
  3. Polls for the expected terminal state ("enrolled")
  """
  use KlassHero.DataCase, async: false

  import KlassHero.Factory

  alias Ecto.Adapters.SQL.Sandbox
  alias KlassHero.Enrollment
  alias KlassHero.Enrollment.Adapters.Driving.Events.InviteFamilyReadyHandler
  alias KlassHero.Enrollment.BulkEnrollmentInvite
  alias KlassHero.Enrollment.ClaimResult
  alias KlassHero.Family
  # EventSubscriber process names that participate in the saga.
  # These GenServers receive PubSub integration events and access the DB.
  alias KlassHero.Family.Adapters.Driving.Events.FamilyEventHandler
  alias KlassHero.Family.Adapters.Driving.Events.InviteClaimedHandler
  alias KlassHero.Provider.Adapters.Driving.Events.ProviderEventHandler
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Events.ObanOutbox
  alias KlassHero.Shared.Adapters.Driven.Events.PubSubIntegrationEventPublisher

  @saga_subscribers [
    # Handles integration:enrollment:invite_claimed -> creates parent + child
    InviteClaimedHandler,
    # Handles integration:family:invite_family_ready -> creates enrollment
    InviteFamilyReadyHandler,
    # Handles integration:accounts:user_registered -> creates parent profile (may race)
    FamilyEventHandler,
    # Handles integration:accounts:user_registered -> creates provider profile stub
    ProviderEventHandler
  ]

  defp create_claimable_invite(_context) do
    import Ecto.Query

    provider = insert(:provider_profile_schema)

    program =
      insert(:program_schema,
        provider_id: provider.id
      )

    token = "saga-test-#{System.unique_integer([:positive])}"
    email = "saga-test-#{System.unique_integer([:positive])}@example.com"

    {:ok, _} =
      KlassHero.Enrollment.create_invite(%{
        program_id: program.id,
        provider_id: provider.id,
        child_first_name: "Emma",
        child_last_name: "Schmidt",
        child_date_of_birth: ~D[2016-03-15],
        guardian_email: email,
        guardian_first_name: "Anna",
        guardian_last_name: "Schmidt"
      })

    invite =
      BulkEnrollmentInvite
      |> where([i], i.guardian_email == ^email and i.program_id == ^program.id)
      |> Repo.one!()

    # Transition invite to "invite_sent" with a token so it can be claimed
    invite
    |> Ecto.Changeset.change(%{invite_token: token, status: :invite_sent})
    |> Repo.update!()

    updated_invite =
      BulkEnrollmentInvite
      |> where([i], i.id == ^invite.id)
      |> Repo.one!()

    %{
      invite: updated_invite,
      token: token,
      program: program,
      provider: provider,
      email: email
    }
  end

  describe "full invite claim saga" do
    setup context do
      # Trigger: provider_profile_schema factory calls unconfirmed_user_fixture(:provider)
      # Why: with real PubSub, ProviderEventHandler receives user_registered and creates a
      #      provider profile — then factory's Repo.insert! duplicates the identity_id → crash
      # Outcome: create test data FIRST with test publisher, then swap to real PubSub
      invite_data = create_claimable_invite(context)

      # Trigger: test config uses TestOutbox (process dictionary storage)
      # Why: PromoteIntegrationEvents handlers must actually broadcast to PubSub so the
      #      EventSubscriber GenServers receive the events and drive the saga forward
      # Outcome: swap to real PubSub publisher for this test, restore in on_exit
      original_config = Application.get_env(:klass_hero, :integration_event_publisher)

      Application.put_env(:klass_hero, :integration_event_publisher,
        module: PubSubIntegrationEventPublisher,
        pubsub: KlassHero.PubSub
      )

      # The saga now crosses both transports: Enrollment stages `invite_claimed` in the
      # outbox, Family still publishes `invite_family_ready`. Both have to be real for
      # the chain to run end to end; the second swap goes when the last producer moves.
      original_outbox = Application.get_env(:klass_hero, :outbox)
      Application.put_env(:klass_hero, :outbox, module: ObanOutbox)

      on_exit(fn ->
        Application.put_env(:klass_hero, :integration_event_publisher, original_config)
        Application.put_env(:klass_hero, :outbox, original_outbox)
      end)

      # Trigger: EventSubscriber GenServers run in separate processes outside the test
      # Why: they need DB access to handle integration events (create parent, child, enrollment)
      # Outcome: allow each subscriber to share the test process's sandboxed connection
      Enum.each(@saga_subscribers, fn subscriber_name ->
        case Process.whereis(subscriber_name) do
          nil -> :ok
          pid -> Sandbox.allow(KlassHero.Repo, self(), pid)
        end
      end)

      invite_data
    end

    test "claim_invite triggers the full saga: user -> registered -> family -> enrolled", %{
      token: token,
      invite: invite
    } do
      # Step 1: Claim the invite. MarkInviteRegistered runs synchronously on the bus;
      # the cross-context event is staged in the same transaction, not published.
      #
      # Manual mode, then an explicit drain, is what makes this test model production:
      # under the suite's `testing: :inline`, staging would execute the delivery job
      # inside the producer's transaction, which is a sequencing production never has.
      assert {:ok, %ClaimResult{user_type: :new_user, user: user}} =
               Oban.Testing.with_testing_mode(:manual, fn -> Enrollment.claim_invite(token) end)

      # Step 2: Verify the synchronous effect of the bus handler.
      updated = Repo.get!(BulkEnrollmentInvite, invite.id)
      assert updated.status == :registered
      assert updated.registered_at != nil

      # Step 3: Deliver the staged event, as a queue worker would after the commit.
      # with_recursion so events staged by the handlers this drains are drained too.
      Oban.drain_queue(queue: :critical_events, with_recursion: true)

      # Step 4: The remainder still travels by PubSub — Family publishes
      # :invite_family_ready, and Enrollment's subscriber creates the enrollment.
      assert_eventually(
        fn ->
          final = Repo.get!(BulkEnrollmentInvite, invite.id)
          final.status == :enrolled
        end,
        timeout_ms: 5000,
        interval_ms: 100
      )

      # Verify terminal invite state
      final = Repo.get!(BulkEnrollmentInvite, invite.id)
      assert final.status == :enrolled
      assert final.enrolled_at != nil
      assert final.enrollment_id != nil

      # Verify family was created
      assert {:ok, parent} = Family.get_parent_by_identity(user.id)
      children = Family.get_children(parent.id)
      assert [_ | _] = children
      assert Enum.any?(children, &(&1.first_name == "Emma"))
    end
  end
end
