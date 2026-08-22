defmodule KlassHero.Participation.SessionAuthorizationTest do
  @moduledoc """
  Who may write a child's attendance record (#1353).

  The fall-through order — provider, then staff, then admin — is the whole
  authorization policy, so it is pinned here rather than left to the callers.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Accounts.Scope
  alias KlassHero.AccountsFixtures
  alias KlassHero.Participation.SessionAuthorization
  alias KlassHero.Provider
  alias KlassHero.ProviderFixtures

  describe "authorize/2" do
    test "a provider owning the program is authorized as :provider" do
      %{provider: provider, session: session} = provider_with_session()
      scope = scope_for(provider_profile: provider)

      assert {:ok, :provider} = SessionAuthorization.authorize(scope, session)
    end

    test "a provider is refused on another provider's program" do
      %{provider: provider} = provider_with_program()
      %{session: foreign_session} = provider_with_session()
      scope = scope_for(provider_profile: provider)

      assert {:error, :unauthorized} = SessionAuthorization.authorize(scope, foreign_session)
    end

    test "a staff member assigned to the program is authorized as :staff" do
      %{provider: provider, program: program, session: session} = provider_with_session()
      staff = assigned_staff(provider, program)
      scope = scope_for(staff_member: staff)

      assert {:ok, :staff} = SessionAuthorization.authorize(scope, session)
    end

    test "a staff member with no assignment to the program is refused" do
      %{provider: provider, session: session} = provider_with_session()
      staff = ProviderFixtures.staff_member_fixture(%{provider_id: provider.id})
      scope = scope_for(staff_member: staff)

      assert {:error, :unauthorized} = SessionAuthorization.authorize(scope, session)
    end

    test "a platform admin holding no persona is authorized as :admin" do
      %{session: session} = provider_with_session()
      # `user_fixture/1`, not `unconfirmed_user_fixture/1` — `registration_changeset`
      # never casts `is_admin`, so the unconfirmed variant drops the flag silently.
      scope = scope_for(user: AccountsFixtures.user_fixture(is_admin: true))

      assert {:ok, :admin} = SessionAuthorization.authorize(scope, session)
    end

    test "a user with no persona and no admin flag is refused" do
      %{session: session} = provider_with_session()

      assert {:error, :unauthorized} = SessionAuthorization.authorize(scope_for([]), session)
    end
  end

  # The write path is the one the issue's acceptance criteria never mentioned: the
  # LiveViews could all be closed and this would still have accepted the check-in.
  # `authorize/2` itself is unchanged — the refusal arrives through the read model.
  describe "authorize/2 and Closed Programs (#1082)" do
    test "a staff member assigned to the program is refused once it closes" do
      %{provider: provider, program: program, session: session} = provider_with_closed_session()
      scope = scope_for(staff_member: assigned_staff(provider, program))

      assert {:error, :unauthorized} = SessionAuthorization.authorize(scope, session)
    end

    test "a staff member overridden onto that one session is refused too" do
      %{provider: provider, program: program, session: session} = provider_with_closed_session()
      staff = ProviderFixtures.staff_member_fixture(%{provider_id: provider.id})

      {:ok, _} =
        Provider.assign_staff_to_session(%{
          provider_id: provider.id,
          program_id: program.id,
          session_id: session.id,
          staff_member_id: staff.id
        })

      assert {:error, :unauthorized} =
               SessionAuthorization.authorize(scope_for(staff_member: staff), session)
    end

    test "the owning provider still corrects their own closed roster" do
      %{provider: provider, session: session} = provider_with_closed_session()

      assert {:ok, :provider} =
               SessionAuthorization.authorize(scope_for(provider_profile: provider), session)
    end

    test "an admin still reaches a closed program" do
      %{session: session} = provider_with_closed_session()
      scope = scope_for(user: AccountsFixtures.user_fixture(is_admin: true))

      assert {:ok, :admin} = SessionAuthorization.authorize(scope, session)
    end

    test "a staff member keeps access while the program is inside its grace window" do
      provider = ProviderFixtures.provider_profile_fixture()

      program =
        insert(:program_schema, provider_id: provider.id, end_date: Date.add(Date.utc_today(), -1))

      session = insert(:program_session_schema, program_id: program.id)
      scope = scope_for(staff_member: assigned_staff(provider, program))

      assert {:ok, :staff} = SessionAuthorization.authorize(scope, session)
    end
  end

  # These four pin the fall-through order itself. Each one returns a different
  # role under a different precedence, so they are what fails if the order is
  # ever reshuffled — the single-persona cases above pass under all of them.
  describe "authorize/2 fall-through order" do
    test "an admin who owns the program is authorized as :provider, not :admin" do
      %{provider: provider, session: session} = provider_with_session()

      scope =
        scope_for(
          user: AccountsFixtures.user_fixture(is_admin: true),
          provider_profile: provider
        )

      assert {:ok, :provider} = SessionAuthorization.authorize(scope, session)
    end

    test "an admin who does not own the program falls through to :admin" do
      %{provider: provider} = provider_with_program()
      %{session: foreign_session} = provider_with_session()

      scope =
        scope_for(
          user: AccountsFixtures.user_fixture(is_admin: true),
          provider_profile: provider
        )

      assert {:ok, :admin} = SessionAuthorization.authorize(scope, foreign_session)
    end

    test "a provider who is also staff is authorized as :provider on their own program" do
      %{provider: provider, program: program, session: session} = provider_with_session()
      staff = assigned_staff(provider, program)
      scope = scope_for(provider_profile: provider, staff_member: staff)

      assert {:ok, :provider} = SessionAuthorization.authorize(scope, session)
    end

    test "a provider who is also staff elsewhere is authorized as :staff on that program" do
      %{provider: own_provider} = provider_with_program()

      %{provider: other_provider, program: other_program, session: other_session} =
        provider_with_session()

      staff = assigned_staff(other_provider, other_program)
      scope = scope_for(provider_profile: own_provider, staff_member: staff)

      assert {:ok, :staff} = SessionAuthorization.authorize(scope, other_session)
    end
  end

  # Session grain (#783). Program assignment is the *fallback* the resolver applies
  # when a session carries no overrides — it is not a second rule OR-ed alongside
  # one. These pin the two cases that distinction decides.
  describe "authorize/2 at session grain" do
    test "a staff member removed from one session is refused, though still on the program" do
      %{provider: provider, program: program, session: session} = provider_with_session()
      staff = assigned_staff(provider, program)
      colleague = assigned_staff(provider, program)

      # Removing one member materializes the program roster onto the session and
      # drops that person, leaving the colleague. The program assignment survives,
      # which is exactly why a program-grain check would keep letting them in.
      assert {:ok, _} = Provider.unassign_staff_from_session(session.id, staff.id, provider.id)

      assert {:error, :unauthorized} =
               SessionAuthorization.authorize(scope_for(staff_member: staff), session)

      assert {:ok, :staff} =
               SessionAuthorization.authorize(scope_for(staff_member: colleague), session)
    end

    test "a staff member on the session but not the program is authorized as :staff" do
      %{provider: provider, session: session} = provider_with_session()
      staff = ProviderFixtures.staff_member_fixture(%{provider_id: provider.id})

      assert {:ok, _} =
               Provider.assign_staff_to_session(%{
                 provider_id: provider.id,
                 session_id: session.id,
                 staff_member_id: staff.id
               })

      assert {:ok, :staff} =
               SessionAuthorization.authorize(scope_for(staff_member: staff), session)
    end

    test "a deactivated staff member on the session is refused" do
      %{provider: provider, session: session} = provider_with_session()
      staff = ProviderFixtures.staff_member_fixture(%{provider_id: provider.id})

      assert {:ok, _} =
               Provider.assign_staff_to_session(%{
                 provider_id: provider.id,
                 session_id: session.id,
                 staff_member_id: staff.id
               })

      {:ok, _} = Provider.deactivate_staff_member(staff)

      assert {:error, :unauthorized} =
               SessionAuthorization.authorize(scope_for(staff_member: staff), session)
    end
  end

  # `authorize/2` collapses every refusal to `:unauthorized`, because no attendance
  # caller ever needed to tell them apart. Session lifecycle does: the staff sessions
  # list says "This program has closed" rather than "Unauthorized", and that copy is
  # the only reason this second entry point exists. Same `resolve/2` underneath — the
  # two differ in how much of its answer they pass on, never in how they get it.
  describe "authorize_lifecycle/2" do
    test "grants the same three roles authorize/2 grants" do
      %{provider: provider, program: program, session: session} = provider_with_session()
      admin = AccountsFixtures.user_fixture(is_admin: true)

      assert {:ok, :provider} =
               SessionAuthorization.authorize_lifecycle(scope_for(provider_profile: provider), session)

      assert {:ok, :staff} =
               SessionAuthorization.authorize_lifecycle(
                 scope_for(staff_member: assigned_staff(provider, program)),
                 session
               )

      assert {:ok, :admin} =
               SessionAuthorization.authorize_lifecycle(scope_for(user: admin), session)
    end

    test "names closure as the reason a staff member was refused" do
      %{provider: provider, program: program, session: session} = provider_with_closed_session()
      scope = scope_for(staff_member: assigned_staff(provider, program))

      assert {:error, :program_closed} = SessionAuthorization.authorize_lifecycle(scope, session)
    end

    test "the owning provider is untouched by closure" do
      %{provider: provider, session: session} = provider_with_closed_session()

      assert {:ok, :provider} =
               SessionAuthorization.authorize_lifecycle(scope_for(provider_profile: provider), session)
    end

    # Closure is a staff rule, so it must be asked after the admin branch, not
    # before it — otherwise a person who happens to hold both personas loses the
    # broader one to the narrower one's refusal.
    test "an admin refused as staff is still authorized as :admin" do
      %{provider: provider, program: program, session: session} = provider_with_closed_session()
      staff = assigned_staff(provider, program)
      admin = AccountsFixtures.user_fixture(is_admin: true)

      assert {:ok, :admin} =
               SessionAuthorization.authorize_lifecycle(
                 scope_for(user: admin, staff_member: staff),
                 session
               )
    end

    # `Provider.get_session_staffing/1` answers for any session id at all, so a
    # reason read off `program_closed?` alone would tell any staff-persona caller
    # the closure state of a program they had merely guessed an id for. The reason
    # is "you would have been staff", not "this program is closed".
    test "a staff member who was never on the session learns nothing about closure" do
      %{session: session} = provider_with_closed_session()
      other_provider = ProviderFixtures.provider_profile_fixture()
      stranger = ProviderFixtures.staff_member_fixture(%{provider_id: other_provider.id})

      assert {:error, :unauthorized} =
               SessionAuthorization.authorize_lifecycle(scope_for(staff_member: stranger), session)
    end

    test "an actor with no persona is refused without a reason" do
      %{session: session} = provider_with_closed_session()

      assert {:error, :unauthorized} = SessionAuthorization.authorize_lifecycle(scope_for([]), session)
    end
  end

  defp provider_with_program do
    provider = ProviderFixtures.provider_profile_fixture()
    program = insert(:program_schema, provider_id: provider.id)

    %{provider: provider, program: program}
  end

  defp provider_with_session do
    %{provider: provider, program: program} = provider_with_program()
    session = insert(:program_session_schema, program_id: program.id)

    %{provider: provider, program: program, session: session}
  end

  defp provider_with_closed_session do
    provider = ProviderFixtures.provider_profile_fixture()

    program =
      insert(:program_schema, provider_id: provider.id, end_date: Date.add(Date.utc_today(), -15))

    session =
      insert(:program_session_schema,
        program_id: program.id,
        session_date: Date.add(Date.utc_today(), -20)
      )

    %{provider: provider, program: program, session: session}
  end

  defp assigned_staff(provider, program) do
    staff = ProviderFixtures.staff_member_fixture(%{provider_id: provider.id})

    ProviderFixtures.program_assignment_fixture(%{
      provider_id: provider.id,
      staff_member_id: staff.id,
      program_id: program.id
    })

    staff
  end

  # Scopes are assembled directly rather than through `Scope.resolve_roles/1` so
  # each case pins exactly one persona combination, independent of how the
  # resolver happens to populate them.
  defp scope_for(opts) do
    %Scope{
      user: Keyword.get_lazy(opts, :user, fn -> AccountsFixtures.unconfirmed_user_fixture() end),
      provider: Keyword.get(opts, :provider_profile),
      staff_member: Keyword.get(opts, :staff_member)
    }
  end
end
