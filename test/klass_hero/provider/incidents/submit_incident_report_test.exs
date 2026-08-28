defmodule KlassHero.Provider.Incidents.SubmitIncidentReportTest do
  use KlassHero.DataCase, async: false
  use Mimic

  import Ecto.Query
  import KlassHero.AccountsFixtures, only: [unconfirmed_user_fixture: 1]
  import KlassHero.EmailTestHelper
  import KlassHero.Factory
  import Swoosh.TestAssertions

  alias KlassHero.Accounts.User
  alias KlassHero.Provider.IncidentReport
  alias KlassHero.Provider.SessionDetail
  alias KlassHero.Provider.SubmitIncidentReport
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Storage.StubStorageAdapter
  alias KlassHero.Shared.Tracing.ObanEnqueue

  setup do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id, title: "Art Club")
    user = unconfirmed_user_fixture(%{})

    %{provider: provider, program_id: program.id, user: user}
  end

  defp base_params(provider, program_id, user) do
    %{
      provider_profile_id: provider.id,
      reporter_user_id: user.id,
      reporter_display_name: user.name || "Test Reporter",
      program_id: program_id,
      session_id: nil,
      category: :safety_concern,
      severity: :medium,
      description: "Someone was running in the hallway — no injury but worth flagging.",
      occurred_at: ~U[2026-04-21 15:00:00Z],
      file_binary: nil
    }
  end

  # Production rows get `business_owner_email` populated by `ProviderEventHandler`
  # off the `:user_registered` integration event. The schema factory leaves it nil
  # to keep fixtures FK-minimal, so tests that exercise the notification path
  # backfill explicitly here.
  defp with_owner_email(provider, email \\ "owner@example.com") do
    provider
    |> Ecto.Changeset.change(%{business_owner_email: email})
    |> Repo.update!()
  end

  describe "execute/1 — program scope" do
    test "persists the report under the given program", %{
      provider: p,
      program_id: pg,
      user: u
    } do
      p = with_owner_email(p)
      params = base_params(p, pg, u)

      assert {:ok, report} = SubmitIncidentReport.execute(params)

      stored = Repo.get(IncidentReport, report.id)
      assert stored.program_id == pg
      assert stored.provider_profile_id == p.id
      assert is_nil(stored.photo_url)
    end

    test "fails when program_id does not belong to the provider", %{provider: p, user: u} do
      params = base_params(p, Ecto.UUID.generate(), u)

      assert {:error, errors} = SubmitIncidentReport.execute(params)
      assert errors[:program_id] == "does not belong to this provider"
      refute Repo.exists?(from r in IncidentReport, select: r.id, limit: 1)
    end

    test "rejects invalid domain data without persistence (description too short)",
         %{provider: p, program_id: pg, user: u} do
      params = p |> base_params(pg, u) |> Map.put(:description, "short")

      assert {:error, %Ecto.Changeset{} = changeset} = SubmitIncidentReport.execute(params)
      assert Enum.any?(errors_on(changeset).description, &(&1 =~ "at least 10"))
      refute Repo.exists?(from r in IncidentReport, select: r.id, limit: 1)
    end

    test "persists reporter_display_name as a snapshot", %{provider: p, program_id: pg, user: u} do
      params = p |> base_params(pg, u) |> Map.put(:reporter_display_name, "Maria Schmidt")

      assert {:ok, report} = SubmitIncidentReport.execute(params)
      assert report.reporter_display_name == "Maria Schmidt"

      stored = Repo.get(IncidentReport, report.id)
      assert stored.reporter_display_name == "Maria Schmidt"
    end

    test "rejects when reporter_display_name is blank", %{provider: p, program_id: pg, user: u} do
      params = p |> base_params(pg, u) |> Map.put(:reporter_display_name, "   ")

      assert {:error, %Ecto.Changeset{} = changeset} = SubmitIncidentReport.execute(params)
      assert Enum.any?(errors_on(changeset).reporter_display_name, &(&1 =~ "blank"))
      refute Repo.exists?(from r in IncidentReport, select: r.id, limit: 1)
    end
  end

  describe "execute/1 — session scope" do
    test "persists the report under the given session", %{
      provider: p,
      program_id: pg,
      user: u
    } do
      session = insert(:program_session_schema, program_id: pg)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.insert!(%SessionDetail{
        session_id: session.id,
        program_id: pg,
        program_title: "Art Club",
        provider_id: p.id,
        session_date: ~D[2026-04-21],
        start_time: ~T[09:00:00],
        end_time: ~T[12:00:00],
        status: :scheduled,
        checked_in_count: 0,
        total_count: 0,
        inserted_at: now,
        updated_at: now
      })

      params =
        p
        |> base_params(nil, u)
        |> Map.put(:program_id, nil)
        |> Map.put(:session_id, session.id)

      assert {:ok, report} = SubmitIncidentReport.execute(params)

      # Mirrors the program-scope assertions above. session_id and program_id are
      # mutually exclusive (validate_ownership/1 admits exactly one), so pinning
      # both sides is what distinguishes session scope from program scope.
      stored = Repo.get(IncidentReport, report.id)
      assert stored.session_id == session.id
      assert is_nil(stored.program_id)
      assert stored.provider_profile_id == p.id
      assert is_nil(stored.photo_url)
    end
  end

  describe "execute/1 — photo upload" do
    setup do
      {:ok, storage} = StubStorageAdapter.start_link(name: :"storage_#{System.unique_integer([:positive])}")
      %{storage: storage}
    end

    test "uploads photo and persists URL", %{
      provider: p,
      program_id: pg,
      user: u,
      storage: storage
    } do
      photo_binary = "fake-jpeg-bytes"

      params =
        p
        |> base_params(pg, u)
        |> Map.put(:file_binary, photo_binary)
        |> Map.put(:original_filename, "incident.jpg")
        |> Map.put(:content_type, "image/jpeg")
        |> Map.put(:storage_opts, adapter: StubStorageAdapter, agent: storage)

      assert {:ok, report} = SubmitIncidentReport.execute(params)
      assert report.photo_url =~ "incident-reports/providers/#{p.id}/"
      assert report.photo_url =~ "incident.jpg"
      assert report.original_filename == "incident.jpg"

      assert {:ok, ^photo_binary} =
               StubStorageAdapter.get_uploaded(:private, report.photo_url, agent: storage)
    end

    # Trigger: file_binary supplied without an original_filename (or with a blank one)
    # Why: validating filename presence AFTER upload leaves an orphan in private storage
    # Outcome: short-circuit with an :original_filename validation error and never call the storage adapter
    test "rejects with missing-filename error and never uploads when filename is blank", %{
      provider: p,
      program_id: pg,
      user: u,
      storage: storage
    } do
      params =
        p
        |> base_params(pg, u)
        |> Map.put(:file_binary, "fake-bytes")
        |> Map.put(:original_filename, nil)
        |> Map.put(:storage_opts, adapter: StubStorageAdapter, agent: storage)

      assert {:error, errors} = SubmitIncidentReport.execute(params)
      assert errors[:original_filename] =~ "is required"

      # Storage stub agent should hold no entries — proves we never called upload/4
      assert Agent.get(storage, & &1) == %{}
    end
  end

  describe "execute/1 — incident email pipeline (end-to-end)" do
    # Flush Swoosh's per-process mailbox so each test's assertions are scoped to
    # mail it just sent.
    setup do
      flush_emails()
      :ok
    end

    test "delivers an email to the business owner when reporter is not the owner", %{
      provider: provider,
      program_id: program_id,
      user: reporter
    } do
      provider
      |> Ecto.Changeset.change(%{business_owner_email: "owner@example.com"})
      |> Repo.update!()

      params = base_params(provider, program_id, reporter)

      assert {:ok, _report} = SubmitIncidentReport.execute(params)

      assert_email_sent(fn email ->
        email.to == [{provider.business_name, "owner@example.com"}] and
          email.subject =~ "Art Club"
      end)
    end

    test "skips the notification when the reporter is the provider owner (self-report)", %{
      provider: provider,
      program_id: program_id
    } do
      owner = Repo.get!(User, provider.identity_id)
      provider = with_owner_email(provider)

      params = base_params(provider, program_id, owner)

      assert {:ok, _report} = SubmitIncidentReport.execute(params)

      assert_no_email_sent()
    end

    test "skips the notification when the provider has no business_owner_email on file", %{
      provider: provider,
      program_id: program_id,
      user: reporter
    } do
      # provider has business_owner_email: nil from the factory
      params = base_params(provider, program_id, reporter)

      assert {:ok, _report} = SubmitIncidentReport.execute(params)

      assert_no_email_sent()
    end
  end

  describe "execute/1 — transactional enqueue (#754)" do
    # Trigger: the Oban enqueue returns {:error, _} from inside the persistence
    # transaction. Row insert and email-job insert must commit atomically — a
    # failed enqueue that leaves the report row behind orphans the notification.
    # Outcome: Repo.transaction rolls back, no incident_reports row exists, no
    # :incident_reported event fires, photo (if any) is cleaned up.
    test "rolls back the report when the email enqueue fails", %{
      provider: p,
      program_id: pg,
      user: u
    } do
      p = with_owner_email(p)
      expect(ObanEnqueue, :with_context, fn _worker, _args -> {:error, :enqueue_failed} end)

      params = base_params(p, pg, u)

      assert {:error, :enqueue_failed} = SubmitIncidentReport.execute(params)

      refute Repo.exists?(IncidentReport)
    end

    test "enqueues the notification with the persisted report id and loaded profile",
         %{provider: p, program_id: pg, user: u} do
      p = with_owner_email(p)
      test_pid = self()

      expect(ObanEnqueue, :with_context, fn _worker, args ->
        send(test_pid, {:enqueued, args})
        {:ok, %Oban.Job{id: 1}}
      end)

      params = base_params(p, pg, u)

      assert {:ok, report} = SubmitIncidentReport.execute(params)

      assert_receive {:enqueued, args}
      assert args.incident_report_id == report.id
      assert args.business_owner_email == "owner@example.com"
      assert args.business_name == p.business_name
    end

    test "deletes the uploaded photo when the transaction rolls back", %{
      provider: p,
      program_id: pg,
      user: u
    } do
      p = with_owner_email(p)

      {:ok, storage} =
        StubStorageAdapter.start_link(name: :"storage_#{System.unique_integer([:positive])}")

      expect(ObanEnqueue, :with_context, fn _worker, _args -> {:error, :enqueue_failed} end)

      params =
        p
        |> base_params(pg, u)
        |> Map.put(:file_binary, "fake-jpeg-bytes")
        |> Map.put(:original_filename, "incident.jpg")
        |> Map.put(:storage_opts, adapter: StubStorageAdapter, agent: storage)

      assert {:error, :enqueue_failed} = SubmitIncidentReport.execute(params)

      # Storage stub agent should hold no entries — proves cleanup_photo deleted
      # the upload after the transaction rolled back.
      assert Agent.get(storage, & &1) == %{}
    end
  end
end
