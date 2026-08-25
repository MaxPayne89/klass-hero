defmodule KlassHeroWeb.BookingLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import Ecto.Query
  import KlassHero.Factory
  import Phoenix.LiveViewTest

  alias KlassHero.Enrollment.Enrollment

  describe "BookingLive authentication" do
    test "redirects to login when not authenticated", %{conn: conn} do
      program = insert(:program_schema)
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/programs/#{program.id}/booking")

      # Should redirect to login page
      assert path == ~p"/users/log-in"
    end

    test "renders booking page when authenticated with valid program", %{conn: conn} do
      %{conn: conn} = register_and_log_in_user(%{conn: conn})
      program = insert(:program_schema, title: "Creative Art World")

      {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}/booking")

      assert has_element?(view, "h1", "Enrollment")
      assert render(view) =~ "Creative Art World"
    end
  end

  describe "BookingLive mount validation" do
    setup :register_and_log_in_user

    test "redirects with error flash for invalid program ID format", %{conn: conn} do
      assert {:error, {:redirect, %{to: path, flash: flash}}} =
               live(conn, ~p"/programs/invalid/booking")

      assert path == ~p"/programs"
      # Invalid UUIDs return :not_found, which shows the "not found" message
      assert flash["error"] == "Program not found"
    end

    test "redirects with error flash for non-existent program ID", %{conn: conn} do
      # Use a valid UUID format that doesn't exist in database
      non_existent_uuid = "550e8400-e29b-41d4-a716-446655449999"

      assert {:error, {:redirect, %{to: path, flash: flash}}} =
               live(conn, ~p"/programs/#{non_existent_uuid}/booking")

      assert path == ~p"/programs"
      assert flash["error"] == "Program not found"
    end

    test "redirects with error flash when program is full", %{conn: conn} do
      program = insert(:program_schema)

      # Set enrollment policy with max=1
      {:ok, _policy} =
        KlassHero.Enrollment.set_enrollment_policy(%{
          program_id: program.id,
          max_enrollment: 1
        })

      # Fill the single spot with an enrollment
      insert(:enrollment_schema, program_id: program.id, status: "pending")

      assert {:error, {:redirect, %{to: path, flash: flash}}} =
               live(conn, ~p"/programs/#{program.id}/booking")

      assert path == ~p"/programs/#{program.id}"
      assert flash["error"] =~ "currently full"
    end

    test "renders normally when program has unlimited capacity", %{conn: conn} do
      program = insert(:program_schema, title: "Unlimited Spots Program")

      # No enrollment policy set — default is unlimited
      {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}/booking")

      assert has_element?(view, "h1", "Enrollment")
      assert render(view) =~ "Unlimited Spots Program"
    end
  end

  describe "BookingLive pricing display" do
    setup :register_and_log_in_user

    test "displays total matching program price exactly", %{conn: conn} do
      program = insert(:program_schema, price: Decimal.new("149.99"))
      {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}/booking")

      assert has_element?(view, "#payment-summary [data-line-item]", "Program fee:")
      assert has_element?(view, "#payment-summary [data-summary-total]", "Total due today:")
      assert summary_total(view) == "€149.99"

      # No hidden fees: the program fee is the only line item.
      assert line_item_count(view) == 1
    end

    test "a free program's total reads Free, not €0.00", %{conn: conn} do
      program = insert(:program_schema, price: Decimal.new("0.00"))
      {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}/booking")

      assert summary_total(view) == "Free"
    end

    test "total is the same regardless of payment method", %{conn: conn} do
      program = insert(:program_schema, price: Decimal.new("75.00"))
      {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}/booking")

      # Switch to transfer — total unchanged, still no payment-method surcharge
      view
      |> element("[phx-click='select_payment_method'][phx-value-method='transfer']")
      |> render_click()

      assert has_element?(view, "#payment-summary [data-summary-total]", "€75.00")
      assert line_item_count(view) == 1
    end

    test "multi-week program total is still just program price, not multiplied", %{conn: conn} do
      # 8-week program at €50 — total should be €50, NOT €400 (8 × 50)
      program =
        insert(:program_schema,
          price: Decimal.new("50.00"),
          start_date: ~D[2026-03-01],
          end_date: ~D[2026-04-26]
        )

      {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}/booking")

      assert summary_total(view) == "€50.00"
    end
  end

  describe "BookingLive enrollment validation" do
    setup :register_and_log_in_user

    test "keeps typed special requirements on the server so a reconnect can recover them",
         %{conn: conn, user: user} do
      parent = insert(:parent_schema, identity_id: user.id)
      {child, _parent} = insert_child_with_guardian(parent: parent, first_name: "Emma")
      program = insert(:program_schema)
      {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}/booking")

      # The browser sends these as two events: the select changes, then the parent types.
      view
      |> form("#booking-form", %{"child_id" => child.id, "special_requirements" => ""})
      |> render_change()

      html =
        view
        |> form("#booking-form", %{
          "child_id" => child.id,
          "special_requirements" => "Peanut allergy"
        })
        |> render_change()

      # Rendered from the assign, not echoed from the request: without a form-level
      # phx-change the server never sees this text and a reconnect wipes it.
      assert html =~ "Peanut allergy"
    end

    test "selecting a different child prefills requirements rather than keeping stale text",
         %{conn: conn, user: user} do
      parent = insert(:parent_schema, identity_id: user.id)
      {child, _parent} = insert_child_with_guardian(parent: parent, first_name: "Emma")
      program = insert(:program_schema)
      {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}/booking")

      html =
        view
        |> form("#booking-form", %{
          "child_id" => child.id,
          "special_requirements" => "typed before choosing a child"
        })
        |> render_change()

      refute html =~ "typed before choosing a child"
    end

    test "complete_enrollment with missing child_id shows error", %{conn: conn} do
      program = insert(:program_schema)
      {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}/booking")

      html =
        view
        |> form("form[phx-submit='complete_enrollment']", %{
          "child_id" => "",
          "special_requirements" => "Test"
        })
        |> render_submit()

      assert html =~ "Please select a child for enrollment."
    end

    test "complete_enrollment with valid data shows success message", %{conn: conn, user: user} do
      # Create parent profile and child for the logged-in user
      parent = insert(:parent_schema, identity_id: user.id)
      {child, _parent} = insert_child_with_guardian(parent: parent, first_name: "Emma")

      program = insert(:program_schema)
      {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}/booking")

      view
      |> form("form[phx-submit='complete_enrollment']", %{
        "child_id" => child.id,
        "special_requirements" => "No allergies"
      })
      |> render_submit()

      assert_redirect(view, ~p"/dashboard")

      # Verify persisted enrollment has correct amounts
      enrollment =
        KlassHero.Repo.one!(
          from e in Enrollment,
            where: e.program_id == ^program.id,
            select: %{
              subtotal: e.subtotal,
              total_amount: e.total_amount,
              vat_amount: e.vat_amount,
              card_fee_amount: e.card_fee_amount
            }
        )

      assert Decimal.equal?(enrollment.total_amount, program.price)
      assert Decimal.equal?(enrollment.subtotal, program.price)
      assert Decimal.equal?(enrollment.vat_amount, Decimal.new("0.00"))
      assert Decimal.equal?(enrollment.card_fee_amount, Decimal.new("0.00"))
    end

    # NOTE: the cross-family IDOR guard is tested at the context boundary (see
    # create_enrollment_test.exs). The child_id <select> only lists the user's own
    # children, so a LiveView-level test can't submit a foreign id.

    test "back_to_program button navigates to program detail", %{conn: conn} do
      program = insert(:program_schema)
      {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}/booking")

      view
      |> element("[phx-click='back_to_program']")
      |> render_click()

      assert_redirect(view, ~p"/programs/#{program.id}")
    end

    test "select_payment_method updates payment method selection", %{conn: conn} do
      program = insert(:program_schema)
      {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}/booking")

      # Switch to transfer
      view
      |> element("[phx-click='select_payment_method'][phx-value-method='transfer']")
      |> render_click()

      # Switch back to card
      view
      |> element("[phx-click='select_payment_method'][phx-value-method='card']")
      |> render_click()

      # No crash, page still renders
      assert has_element?(view, "h1", "Enrollment")
    end
  end

  # Scope price assertions to the summary card. A `refute html =~ "VAT"` over the whole
  # document flakes: the page's random base64 blobs (csrf-token, phx-session, phx-static)
  # occasionally spell short strings. See #1287.
  defp summary_doc(view) do
    view |> element("#payment-summary") |> render() |> LazyHTML.from_fragment()
  end

  defp line_item_count(view) do
    view |> summary_doc() |> LazyHTML.query("[data-line-item]") |> Enum.count()
  end

  defp summary_total(view) do
    view |> summary_doc() |> LazyHTML.query("[data-summary-total] [data-value]") |> LazyHTML.text()
  end
end
