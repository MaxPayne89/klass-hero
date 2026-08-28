defmodule KlassHeroWeb.Flows.ProviderPublishesProgramTest do
  @moduledoc """
  Flow test for a provider publishing a program: the provider dashboard's program
  form -> `program_created` delivered for real -> the card on the public `/programs`.

  This is the one flow that crosses the CQRS boundary end to end. Today the two
  halves are tested apart and neither can see the seam: `programs_live_test.exs`
  seeds the catalog read path directly, so the publish path never runs, and
  `program_listing_delivery_test.exs` runs the projection but never renders the
  page. A field the producer stops sending is invisible to both — which is how
  `program_created` came to omit description and price (see the fix in
  `KlassHero.ProgramCatalog.listing_payload/1`).

  `ProfileCompletionLive` is deliberately not on this path: it serves the
  staff-to-provider draft upgrade (ADR-0005). A provider who registers directly
  gets `profile_status: :active` and starts at the dashboard.
  """

  use KlassHeroWeb.FlowCase, async: false

  alias KlassHero.Repo

  setup :register_and_log_in_provider

  # "New Program" is disabled until the provider is verified.
  setup %{provider: provider} do
    provider
    |> Ecto.Changeset.change(%{
      verified: true,
      verified_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update!()

    :ok
  end

  describe "publishing a program" do
    test "a program created on the dashboard reaches the public catalog", %{conn: conn} do
      with_real_outbox(fn ->
        conn
        |> visit(~p"/provider/dashboard/programs")
        |> click_button("#new-program-btn", "New Program")
        |> within("#program-form", fn form ->
          form
          |> fill_in("Title", with: "Chess Club")
          |> fill_in("Subtitle", with: "For beginners, no experience needed")
          |> select("Category", option: "Education")
          |> fill_in("Price (EUR)", with: "60.00")
          |> fill_in("Location", with: "Community Center")
          |> fill_in("Description", with: "Develop strategic thinking through chess")
          |> click_button("#save-program-btn", "Save Program")
        end)
      end)

      # A second, unauthenticated visitor: the catalog is public, and the row it
      # reads was written by the publish path, not by this test.
      build_conn()
      |> visit(~p"/programs")
      |> assert_has("#mk-programs-stream", text: "Chess Club")
      |> assert_has("#mk-programs-stream", text: "For beginners, no experience needed")
      |> assert_has("#mk-programs-stream", text: "Develop strategic thinking through chess")
      |> assert_has("#mk-programs-stream", text: "€60.00")
    end
  end
end
