defmodule KlassHeroWeb.Flows.ParentBookingTest do
  @moduledoc """
  Flow test for the parent booking journey: public catalog -> program detail ->
  booking form -> dashboard.

  Each hop is already covered in isolation (`programs_live_test.exs`,
  `program_detail_live_test.exs`, `booking_live_test.exs`). What is new here is the
  chain, and the fact that the program is arranged through
  `Journeys.published_program/1` — so the `/programs` listing is served by a
  `programs` row that the publish path actually wrote, rather
  than one the test inserted into the read table itself.
  """

  use KlassHeroWeb.FlowCase, async: false

  alias KlassHero.Enrollment

  setup :register_and_log_in_user_with_child

  describe "booking a program" do
    test "parent walks from the catalog to a confirmed enrollment", %{
      conn: conn,
      child: child
    } do
      program = published_program(%{title: "Soccer Stars"})

      conn
      |> visit(~p"/programs")
      |> assert_has("#mk-programs-stream", text: "Soccer Stars")
      |> click_link("[data-program-id]", "Soccer Stars")
      |> assert_path(~p"/programs/#{program.id}")
      # Scoped by id: the detail page renders a desktop and a mobile "Book Now".
      |> click_button("#book-now-button", "Book Now")
      |> assert_path(~p"/programs/#{program.id}/booking")
      |> select("Select Child", option: child.first_name, exact_option: false)
      |> click_button("Complete Enrollment")
      |> assert_path(~p"/dashboard")
      |> assert_has("#family-programs-list", text: "Soccer Stars", timeout: 1000)
    end

    test "a required waiver must be ticked on the way through", %{
      conn: conn,
      child: child,
      parent: parent
    } do
      provider = insert(:provider_profile_schema)
      program = published_program(%{provider: provider, title: "Climbing Club"})

      {:ok, %{waiver: waiver}} =
        Enrollment.create_waiver(provider.id, %{
          program_id: program.id,
          title: "Liability Waiver",
          required: true,
          body: "I agree to hold the provider harmless."
        })

      session =
        conn
        |> visit(~p"/programs/#{program.id}/booking")
        |> assert_has("#sign-waiver-#{waiver.id}")
        |> select("Select Child", option: child.first_name, exact_option: false)

      # Submitting unsigned is refused and creates nothing: the parent stays on the
      # booking page rather than reaching the dashboard.
      session
      |> click_button("Complete Enrollment")
      |> assert_has("[role='alert']", text: "sign every required waiver")
      |> assert_path(~p"/programs/#{program.id}/booking")

      assert Enrollment.list_parent_enrollments(parent.id) == []

      session
      |> check("I have read and agree to Liability Waiver")
      |> click_button("Complete Enrollment")
      |> assert_path(~p"/dashboard")
      |> assert_has("#family-programs-list", text: "Climbing Club", timeout: 1000)
    end
  end
end
