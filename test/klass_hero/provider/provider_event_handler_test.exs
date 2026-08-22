defmodule KlassHero.Provider.ProviderEventHandlerTest do
  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures, only: [user_fixture: 1]
  import KlassHero.Factory
  import KlassHero.ProviderFixtures

  alias KlassHero.AccountsFixtures
  alias KlassHero.Provider
  alias KlassHero.Provider.IncidentReport
  alias KlassHero.Provider.ProviderEventHandler
  alias KlassHero.Provider.StaffMember
  alias KlassHero.Shared.Adapters.Driven.Persistence.Repositories.ProcessedEventRepository
  alias KlassHero.Shared.Adapters.Driven.Persistence.Schemas.ProcessedEvent

  describe "handle_event/1 for :user_registered" do
    test "creates provider profile when 'provider' in intended_roles" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])

      event = build_user_registered_event(user)
      assert :ok = ProviderEventHandler.handle_event(event)

      assert {:ok, _profile} = Provider.get_provider_by_identity(user.id)
    end

    test "ignores event when 'provider' not in intended_roles" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:parent])

      event = build_user_registered_event(user, intended_roles: ["parent"])
      assert :ignore = ProviderEventHandler.handle_event(event)
    end

    test "captures business_owner_email from payload" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])

      event = build_user_registered_event(user, email: "owner@example.com")
      assert :ok = ProviderEventHandler.handle_event(event)

      assert {:ok, profile} = Provider.get_provider_by_identity(user.id)
      assert profile.business_owner_email == "owner@example.com"
    end

    test "leaves business_owner_email nil when payload omits :email" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])

      event = build_user_registered_event(user)
      payload = Map.delete(event.payload, :email)
      assert :ok = ProviderEventHandler.handle_event(%{event | payload: payload})

      assert {:ok, profile} = Provider.get_provider_by_identity(user.id)
      assert profile.business_owner_email == nil
    end
  end

  describe "handle_event/1 for :user_anonymized" do
    test "scrubs the Provider-owned PII surfaces for the user" do
      user = user_fixture(intended_roles: [:staff, :provider])
      provider = provider_profile_fixture(identity_id: user.id)
      program = insert(:program_schema, provider_id: provider.id)

      staff =
        staff_member_fixture(provider_id: provider.id, user_id: user.id, first_name: "Jane", email: "jane@example.com")

      report =
        incident_report_fixture(
          provider_profile_id: provider.id,
          reporter_user_id: user.id,
          reporter_display_name: "Jane Whistleblower",
          program_id: program.id
        )

      event = %{event_type: :user_anonymized, entity_id: user.id}
      assert :ok = ProviderEventHandler.handle_event(event)

      assert Repo.get(StaffMember, staff.id).email == nil
      refute Repo.get(StaffMember, staff.id).active
      refute Repo.get(IncidentReport, report.id).reporter_display_name =~ "Jane"
    end

    test "returns :ok when the user owns no Provider data" do
      event = %{event_type: :user_anonymized, entity_id: Ecto.UUID.generate()}
      assert :ok = ProviderEventHandler.handle_event(event)
    end
  end

  describe "handle_event/1 for unknown events" do
    test "returns :ignore" do
      event = %{event_type: :unknown_event, entity_id: Ecto.UUID.generate()}
      assert :ignore = ProviderEventHandler.handle_event(event)
    end
  end

  describe "handle_event/1 for :user_confirmed" do
    test "creates provider profile when 'provider' in intended_roles" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])

      event = build_user_confirmed_event(user)
      assert :ok = ProviderEventHandler.handle_event(event)

      assert {:ok, _profile} = Provider.get_provider_by_identity(user.id)
    end

    test "returns :ok when provider profile already exists (idempotent)" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])

      # First call creates the profile
      registered_event = build_user_registered_event(user)
      assert :ok = ProviderEventHandler.handle_event(registered_event)

      # Second call via user_confirmed is idempotent
      confirmed_event = build_user_confirmed_event(user)
      assert :ok = ProviderEventHandler.handle_event(confirmed_event)

      # Only one profile exists
      assert {:ok, _profile} = Provider.get_provider_by_identity(user.id)
    end

    test "ignores event when 'provider' not in intended_roles" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:parent])

      event = build_user_confirmed_event(user, intended_roles: ["parent"])
      assert :ignore = ProviderEventHandler.handle_event(event)
    end

    test "captures business_owner_email from payload" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])

      event = build_user_confirmed_event(user, email: "confirmed@example.com")
      assert :ok = ProviderEventHandler.handle_event(event)

      assert {:ok, profile} = Provider.get_provider_by_identity(user.id)
      assert profile.business_owner_email == "confirmed@example.com"
    end

    # Regression for #1065. The idempotent test above calls the handler directly
    # (safe out-of-transaction path); this drives it through the exactly-once
    # wrapper production uses (execute_atomically → Repo.transaction). Before the
    # `mode: :savepoint` fix, the duplicate-identity insert poisoned the txn and
    # execute_atomically returned {:error, :rollback}, discarding the Oban job.
    test "is idempotent through execute_atomically when profile already exists (issue #1065)" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])

      # :user_registered has already created the profile.
      assert :ok = ProviderEventHandler.handle_event(build_user_registered_event(user))

      # :user_confirmed compensation now runs inside the atomic transaction.
      event_id = Ecto.UUID.generate()

      handler_fn = fn ->
        ProviderEventHandler.handle_event(build_user_confirmed_event(user))
      end

      result =
        ProcessedEventRepository.execute_atomically(event_id, "ProviderEventHandler", handler_fn)

      # 1. The duplicate is tolerated as idempotent success — not {:error, :rollback}.
      assert result == :ok

      # 2. The dedup marker committed, so Oban won't redeliver forever.
      assert Repo.get_by(ProcessedEvent, event_id: event_id, handler_ref: "ProviderEventHandler")
    end
  end

  describe "subscribed_events/0" do
    test "includes :user_confirmed" do
      assert :user_confirmed in ProviderEventHandler.subscribed_events()
    end
  end

  # Helpers

  defp build_user_registered_event(user, opts \\ []) do
    intended_roles = Keyword.get(opts, :intended_roles, ["provider"])
    email = Keyword.get(opts, :email, user.email)

    %{
      event_type: :user_registered,
      entity_id: user.id,
      payload: %{
        intended_roles: intended_roles,
        name: user.name || "Test Provider",
        email: email
      }
    }
  end

  defp build_user_confirmed_event(user, opts \\ []) do
    intended_roles = Keyword.get(opts, :intended_roles, ["provider"])
    email = Keyword.get(opts, :email, user.email)

    %{
      event_type: :user_confirmed,
      entity_id: user.id,
      payload: %{
        intended_roles: intended_roles,
        name: user.name || "Test Provider",
        email: email
      }
    }
  end
end
