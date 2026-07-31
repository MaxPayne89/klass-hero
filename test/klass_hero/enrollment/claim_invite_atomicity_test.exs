defmodule KlassHero.Enrollment.ClaimInviteAtomicityTest do
  @moduledoc """
  The invite is marked registered and `invite_claimed` is staged in one
  transaction, so neither can happen without the other.

  Before the bus was deleted the two were separate: a `MarkInviteRegistered`
  handler ran the transition synchronously during dispatch, and staging followed
  it, ungated. A staging failure therefore left a registered invite whose claim
  no consumer ever heard about.

  `async: false` — swapping the `:outbox` adapter is application-global.
  """
  use KlassHero.DataCase, async: false

  import KlassHero.AccountsFixtures
  import KlassHero.Factory

  alias KlassHero.Enrollment
  alias KlassHero.Enrollment.BulkEnrollmentInvite
  alias KlassHero.Enrollment.ClaimInvite
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Events.TestOutbox

  defmodule RaisingOutbox do
    @moduledoc false
    @behaviour KlassHero.Shared.ForStagingEvents

    @impl true
    def stage(_events), do: raise("outbox is down")
  end

  setup do
    unique = System.unique_integer([:positive])
    token = "atomicity-#{unique}"
    email = "atomicity-#{unique}@example.com"

    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)

    # An existing guardian, so `resolve_user/1` takes the lookup path. Registering a
    # new user would stage `user_registered` and hit the raising adapter before the
    # claim this test is about.
    user_fixture(%{email: email})

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
      |> Repo.get_by!(guardian_email: email)
      |> Ecto.Changeset.change(%{invite_token: token, status: :invite_sent})
      |> Repo.update!()

    # Discard the fixtures' own staged events (user_registered and friends) so the
    # assertions below see only what claiming produced.
    TestOutbox.setup()

    %{invite: invite, token: token}
  end

  test "a staging failure leaves the invite unclaimed", %{invite: invite, token: token} do
    Application.put_env(:klass_hero, :outbox, module: RaisingOutbox)
    on_exit(fn -> Application.put_env(:klass_hero, :outbox, module: TestOutbox) end)

    assert_raise RuntimeError, "outbox is down", fn -> ClaimInvite.execute(token) end

    assert %{status: :invite_sent, registered_at: nil} = Repo.get!(BulkEnrollmentInvite, invite.id)
  end

  test "a successful claim registers the invite and stages the event together", %{invite: invite, token: token} do
    assert {:ok, _result} = ClaimInvite.execute(token)

    assert %{status: :registered, registered_at: %DateTime{}} = Repo.get!(BulkEnrollmentInvite, invite.id)
    assert [%{event_type: :invite_claimed}] = TestOutbox.staged()
  end

  # The claim checks claimability twice: once before opening the transaction, once
  # inside it. Two concurrent claims of one token both clear the first check, so the
  # loser reaches the write with a row that has already moved on. It has to be told
  # the invite is spoken for — a bare transition would reject :registered -> :registered
  # with a changeset error, which `InviteClaimController` has no clause for.
  #
  # Exercised through the in-transaction check directly, since the two requests cannot
  # be interleaved deterministically from a single sandboxed connection.
  test "the loser of a concurrent claim is told the invite is already claimed", %{invite: invite, token: token} do
    assert {:ok, _first} = ClaimInvite.execute(token)

    assert {:error, :already_claimed} = Enrollment.register_claimed_invite(invite.id)
  end

  test "registering an invite that vanished reports not_found" do
    assert {:error, :not_found} = Enrollment.register_claimed_invite(Ecto.UUID.generate())
  end

  # `resolve_user/1` checks for an account and then creates one, and the two are not atomic.
  # A guardian who double-clicks their invite link — or whose email client prefetches the URL —
  # registers twice concurrently, and the loser gets a duplicate-email changeset. Before #1215
  # that changeset reached `InviteClaimController`, which has no clause for it.
  #
  # Driven through the post-race step directly, for the same reason as the concurrent-claim
  # test above: the two requests cannot be interleaved from one sandboxed connection.
  test "the loser of a registration race resolves to the winner's account", %{invite: invite} do
    assert {:ok, :existing_user, user} = ClaimInvite.resolve_after_conflict(invite)

    assert user.email == invite.guardian_email
  end

  # The row lock means a loser normally blocks, re-reads `:registered`, and is answered by
  # `ensure_claimable/1` before a changeset exists. This pins the shape underneath it: a
  # re-registration attempt is somebody else's claim, and the raw error it produces carries
  # no `validation:` tag — `get_change/2` is nil when the value already matches, so
  # `validate_status_transition` reports "status change is required", not an illegal
  # transition. The classifier keys on the field for exactly that reason.
  test "re-registering an already-registered invite errors on :status, untagged", %{invite: invite} do
    {:ok, registered} = Enrollment.register_claimed_invite(invite.id)

    assert {:error, %Ecto.Changeset{errors: errors}} =
             Enrollment.transition_invite(registered, %{status: :registered})

    assert Keyword.has_key?(errors, :status)
  end

  test "a second registration of one invite is reported as already claimed", %{invite: invite} do
    assert {:ok, _} = Enrollment.register_claimed_invite(invite.id)

    assert {:error, :already_claimed} = Enrollment.register_claimed_invite(invite.id)
  end

  test "a reported conflict with no resolvable account gives up gracefully" do
    orphan = %BulkEnrollmentInvite{
      id: Ecto.UUID.generate(),
      guardian_email: "no-such-guardian-#{System.unique_integer([:positive])}@example.com"
    }

    assert {:error, :registration_failed} = ClaimInvite.resolve_after_conflict(orphan)
  end
end
