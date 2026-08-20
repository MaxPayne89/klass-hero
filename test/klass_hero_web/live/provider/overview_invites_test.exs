defmodule KlassHeroWeb.Provider.OverviewInvitesTest do
  @moduledoc """
  Covers the Overview tab's cross-program outstanding-invitations card (#1073).

  The card aggregates every invite the provider has sent that nobody has accepted
  yet. Before #1073 this path was never exercised by a test: the LiveView built its
  card rows from fields that do not exist on `BulkEnrollmentInvite`, so merely
  mounting Overview with one such invite raised. The mount tests below are that
  missing coverage.
  """
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias KlassHero.Enrollment
  alias KlassHero.Enrollment.BulkEnrollmentInvite
  alias KlassHero.ProgramCatalog.ProgramListing
  alias KlassHero.Repo

  setup :register_and_log_in_provider

  # Overview reads programs from the program_listings read table and derives its
  # KPI counts from them — a write-side program alone leaves the tab half-empty.
  defp insert_program_with_listing(attrs) do
    program = KlassHero.Factory.insert(:program_schema, attrs)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %ProgramListing{}
    |> Ecto.Changeset.change(%{
      id: program.id,
      title: program.title,
      description: program.description,
      category: program.category,
      age_range: program.age_range,
      price: program.price,
      pricing_period: program.pricing_period,
      location: program.location,
      start_date: program.start_date,
      end_date: program.end_date,
      meeting_days: program.meeting_days || [],
      season: program.season,
      provider_id: program.provider_id,
      inserted_at: program.inserted_at || now,
      updated_at: program.updated_at || now
    })
    |> Repo.insert!()

    program
  end

  defp invite(program, provider, attrs \\ %{}) do
    {status, attrs} = Map.pop(attrs, :status)

    {:ok, invite} =
      Enrollment.create_invite(
        Map.merge(
          %{
            program_id: program.id,
            provider_id: provider.id,
            child_first_name: "Jane",
            child_last_name: "Smith",
            child_date_of_birth: ~D[2015-06-15],
            guardian_email: "guardian@test.com"
          },
          attrs
        )
      )

    case status do
      nil -> invite
      status -> invite |> Ecto.Changeset.change(%{status: status}) |> Repo.update!()
    end
  end

  defp open_modal(conn) do
    {:ok, view, _html} = live(conn, ~p"/provider/dashboard")
    view |> element("#open-outstanding-invites") |> render_click()
    view
  end

  setup %{provider: provider} do
    %{program: insert_program_with_listing(provider_id: provider.id, title: "Chess Club")}
  end

  describe "the card" do
    # An invite sits in :pending between creation and the email worker, and every
    # "Resend" click returns it there — an ordinary state, not an edge case. It
    # crashed the whole Overview page (a KeyError in mount/3) before #1073.
    for status <- [:pending, :invite_sent, :failed] do
      test "mounts and counts a #{status} invite", %{
        conn: conn,
        program: program,
        provider: provider
      } do
        invite(program, provider, %{status: unquote(status)})

        {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

        assert has_element?(view, "#outstanding-invites-card")
        assert has_element?(view, "#open-outstanding-invites")
        assert view |> element("#outstanding-invites-count") |> render() =~ "1"
      end
    end

    # The old card filtered on :pending alone, so it read empty in production while
    # invites sat unanswered in :invite_sent. That mis-filter was the reported gap.
    for status <- [:registered, :enrolled] do
      test "ignores an answered #{status} invite", %{
        conn: conn,
        program: program,
        provider: provider
      } do
        invite(program, provider, %{status: unquote(status)})

        {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

        assert has_element?(view, "#outstanding-invites-card-empty")
        refute has_element?(view, "#open-outstanding-invites")
      end
    end

    test "shows the empty state when nothing is outstanding", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

      assert has_element?(view, "#outstanding-invites-card-empty")
    end

    test "counts invites from every program the provider runs", %{
      conn: conn,
      program: program,
      provider: provider
    } do
      other = insert_program_with_listing(provider_id: provider.id, title: "Art Club")
      invite(program, provider)
      invite(other, provider, %{guardian_email: "second@test.com"})

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

      assert view |> element("#outstanding-invites-count") |> render() =~ "2"
    end
  end

  describe "the modal" do
    setup %{program: program, provider: provider} do
      %{invite: invite(program, provider)}
    end

    test "opens, names the program each invite belongs to, and closes", %{conn: conn} do
      view = open_modal(conn)

      assert has_element?(view, "#outstanding-invites-modal")
      assert has_element?(view, "#outstanding-invites-table")
      assert render(view) =~ "Chess Club"

      view |> element("#close-outstanding-invites") |> render_click()

      refute has_element?(view, "#outstanding-invites-modal")
    end

    test "offers Resend and Remove on each row", %{conn: conn, invite: invite} do
      view = open_modal(conn)

      assert has_element?(view, "#invite-#{invite.id} [phx-click=resend_invite]")
      assert has_element?(view, "#invite-#{invite.id} [phx-click=delete_invite]")
    end

    test "Remove drops the invite and updates the count", %{conn: conn, invite: invite} do
      view = open_modal(conn)

      view
      |> element("#invite-#{invite.id} [phx-click=delete_invite]")
      |> render_click()

      refute has_element?(view, "#invite-#{invite.id}")
      assert has_element?(view, "#outstanding-invites-card-empty")
    end

    # No `with_testing_mode(:manual, ...)` here, deliberately: it is process-scoped,
    # and `render_click` runs the work in the LiveView's process, not the test's — so
    # the override would not reach the enqueue and would only look like a guard.
    # Under the suite's `testing: :inline` the email worker therefore runs and carries
    # the invite :pending -> :invite_sent. Both are outstanding, so it stays listed.
    test "Resend reopens the invite and keeps it listed", %{conn: conn, invite: invite} do
      view = open_modal(conn)

      view
      |> element("#invite-#{invite.id} [phx-click=resend_invite]")
      |> render_click()

      assert has_element?(view, "#invite-#{invite.id}")

      # `resent_at` is the durable evidence the resend path ran (#1339's watermark);
      # the status alone cannot distinguish a resend from the original send.
      reloaded = Repo.reload!(invite)
      assert reloaded.resent_at
      assert reloaded.status in BulkEnrollmentInvite.outstanding_statuses()
    end
  end
end
