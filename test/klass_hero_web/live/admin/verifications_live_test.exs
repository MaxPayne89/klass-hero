defmodule KlassHeroWeb.Admin.VerificationsLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.Factory
  import Phoenix.LiveViewTest

  # Authentication & Authorization

  describe "authentication" do
    test "unauthenticated user is redirected from index", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/admin/verifications")
      assert {:redirect, %{to: to}} = redirect
      assert to =~ "/users/log-in"
    end

    test "unauthenticated user is redirected from show", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/admin/verifications/#{Ecto.UUID.generate()}")
      assert {:redirect, %{to: to}} = redirect
      assert to =~ "/users/log-in"
    end
  end

  describe "authorization" do
    setup :register_and_log_in_user

    test "non-admin user is redirected from index with error flash", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/admin/verifications")
      assert {:redirect, %{to: "/", flash: flash}} = redirect
      assert flash["error"] =~ "access"
    end

    test "non-admin user is redirected from show with error flash", %{conn: conn} do
      assert {:error, redirect} =
               live(conn, ~p"/admin/verifications/#{Ecto.UUID.generate()}")

      assert {:redirect, %{to: "/", flash: flash}} = redirect
      assert flash["error"] =~ "access"
    end
  end

  # Index Page

  describe "index page" do
    setup :register_and_log_in_admin

    test "renders page with verification documents", %{conn: conn} do
      doc = insert(:verification_document_schema)

      {:ok, view, _html} = live(conn, ~p"/admin/verifications")

      assert has_element?(view, "h1", "Verifications")
      assert has_element?(view, "#doc-#{doc.id}")
    end

    test "renders empty state when no documents", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/verifications")

      assert has_element?(view, "h1", "Verifications")
      # The count display should show "0 documents"
      assert render(view) =~ "0 documents"
    end

    test "displays document info in list", %{conn: conn} do
      provider = insert(:provider_profile_schema, business_name: "Acme Sports")

      doc =
        insert(:verification_document_schema,
          provider_profile_id: provider.id,
          document_type: :insurance_certificate,
          original_filename: "insurance.pdf"
        )

      {:ok, view, _html} = live(conn, ~p"/admin/verifications")

      html = render(view)
      assert html =~ "Acme Sports"
      assert html =~ "Insurance Certificate"
      assert html =~ "insurance.pdf"
      assert has_element?(view, "#doc-#{doc.id}")
    end

    test "links to detail page", %{conn: conn} do
      doc = insert(:verification_document_schema)

      {:ok, view, _html} = live(conn, ~p"/admin/verifications")

      assert has_element?(view, "a[href='/admin/verifications/#{doc.id}']")
    end

    test "surfaces the registration number on a business-registration row without opening the file",
         %{conn: conn} do
      provider =
        insert(:provider_profile_schema,
          entity_type: :business,
          legal_business_name: "Acme Trading GmbH",
          registration_number: "HRB 98765"
        )

      doc =
        insert(:verification_document_schema,
          provider_profile_id: provider.id,
          document_type: :business_registration
        )

      {:ok, view, _html} = live(conn, ~p"/admin/verifications")

      assert has_element?(view, "#doc-#{doc.id}", "HRB 98765")
    end

    test "filters by pending status", %{conn: conn} do
      pending = insert(:verification_document_schema, status: :pending)
      approved = insert(:approved_verification_document_schema)

      {:ok, view, _html} = live(conn, ~p"/admin/verifications?status=pending")

      assert has_element?(view, "#doc-#{pending.id}")
      refute has_element?(view, "#doc-#{approved.id}")
    end

    test "filters by approved status", %{conn: conn} do
      pending = insert(:verification_document_schema, status: :pending)
      approved = insert(:approved_verification_document_schema)

      {:ok, view, _html} = live(conn, ~p"/admin/verifications?status=approved")

      refute has_element?(view, "#doc-#{pending.id}")
      assert has_element?(view, "#doc-#{approved.id}")
    end

    test "filters by rejected status", %{conn: conn} do
      pending = insert(:verification_document_schema, status: :pending)
      rejected = insert(:rejected_verification_document_schema)

      {:ok, view, _html} = live(conn, ~p"/admin/verifications?status=rejected")

      refute has_element?(view, "#doc-#{pending.id}")
      assert has_element?(view, "#doc-#{rejected.id}")
    end

    test "shows all documents when no status filter", %{conn: conn} do
      pending = insert(:verification_document_schema, status: :pending)
      approved = insert(:approved_verification_document_schema)

      {:ok, view, _html} = live(conn, ~p"/admin/verifications")

      assert has_element?(view, "#doc-#{pending.id}")
      assert has_element?(view, "#doc-#{approved.id}")
    end

    test "filter tabs navigate via patch", %{conn: conn} do
      insert(:verification_document_schema)

      {:ok, view, _html} = live(conn, ~p"/admin/verifications")

      assert has_element?(view, "#verification-filters")
      assert has_element?(view, "a[href='/admin/verifications?status=pending']", "Pending")
      assert has_element?(view, "a[href='/admin/verifications?status=approved']", "Approved")
      assert has_element?(view, "a[href='/admin/verifications?status=rejected']", "Rejected")
      assert has_element?(view, "a[href='/admin/verifications']", "All")
    end
  end

  # Show Page

  describe "show page" do
    setup :register_and_log_in_admin

    test "renders document details", %{conn: conn} do
      provider = insert(:provider_profile_schema, business_name: "Youth Academy")

      doc =
        insert(:verification_document_schema,
          provider_profile_id: provider.id,
          document_type: :business_registration,
          original_filename: "business_reg.pdf"
        )

      {:ok, view, _html} = live(conn, ~p"/admin/verifications/#{doc.id}")

      assert has_element?(view, "h1", "Business Registration")
      assert has_element?(view, "#document-info")

      html = render(view)
      assert html =~ "Youth Academy"
      assert html =~ "business_reg.pdf"
    end

    test "renders document preview section", %{conn: conn} do
      doc = insert(:verification_document_schema)

      {:ok, view, _html} = live(conn, ~p"/admin/verifications/#{doc.id}")

      assert has_element?(view, "#document-preview")
    end

    test "surfaces the legal name and registration number for a business-registration document",
         %{conn: conn} do
      provider =
        insert(:provider_profile_schema,
          entity_type: :business,
          business_name: "Acme Trading",
          legal_business_name: "Acme Trading GmbH",
          registration_number: "HRB 98765"
        )

      doc =
        insert(:verification_document_schema,
          provider_profile_id: provider.id,
          document_type: :business_registration
        )

      {:ok, view, _html} = live(conn, ~p"/admin/verifications/#{doc.id}")

      assert has_element?(view, "#document-info", "Acme Trading GmbH")
      assert has_element?(view, "#document-info", "HRB 98765")
    end

    test "omits the registration fields for a non-business document", %{conn: conn} do
      doc = insert(:verification_document_schema, document_type: :insurance_certificate)

      {:ok, view, _html} = live(conn, ~p"/admin/verifications/#{doc.id}")

      refute has_element?(view, "#document-info dt", "Registration number")
    end

    test "shows the policy expiry with an Expired badge for a lapsed insurance certificate", %{conn: conn} do
      doc =
        insert(:verification_document_schema,
          document_type: :insurance_certificate,
          expiry_date: Date.add(Date.utc_today(), -1)
        )

      {:ok, view, _html} = live(conn, ~p"/admin/verifications/#{doc.id}")

      assert has_element?(view, "#document-expiry", "Expired")
    end

    test "omits the expiry row when the document has no expiry date", %{conn: conn} do
      doc = insert(:verification_document_schema, document_type: :background_check, expiry_date: nil)

      {:ok, view, _html} = live(conn, ~p"/admin/verifications/#{doc.id}")

      refute has_element?(view, "#document-expiry")
    end

    test "renders an inline video player for a video-screening document", %{conn: conn} do
      doc =
        insert(:verification_document_schema,
          document_type: "video_screening",
          original_filename: "screening.mp4"
        )

      {:ok, view, _html} = live(conn, ~p"/admin/verifications/#{doc.id}")

      assert has_element?(view, "#document-preview video")
    end

    test "renders action buttons for pending documents", %{conn: conn} do
      doc = insert(:verification_document_schema, status: :pending)

      {:ok, view, _html} = live(conn, ~p"/admin/verifications/#{doc.id}")

      assert has_element?(view, "#review-actions")
      assert has_element?(view, "#approve-button")
      assert has_element?(view, "#reject-button")
    end

    test "hides action buttons for approved documents", %{conn: conn} do
      doc = insert(:approved_verification_document_schema)

      {:ok, view, _html} = live(conn, ~p"/admin/verifications/#{doc.id}")

      refute has_element?(view, "#review-actions")
      refute has_element?(view, "#approve-button")
    end

    test "hides action buttons for rejected documents", %{conn: conn} do
      doc = insert(:rejected_verification_document_schema)

      {:ok, view, _html} = live(conn, ~p"/admin/verifications/#{doc.id}")

      refute has_element?(view, "#review-actions")
      refute has_element?(view, "#reject-button")
    end

    test "shows rejection reason for rejected documents", %{conn: conn} do
      doc =
        insert(:rejected_verification_document_schema,
          rejection_reason: "Missing signature"
        )

      {:ok, view, _html} = live(conn, ~p"/admin/verifications/#{doc.id}")

      assert has_element?(view, "#rejection-reason")
      assert render(view) =~ "Missing signature"
    end

    test "redirects with error flash when document not found", %{conn: conn} do
      fake_id = Ecto.UUID.generate()

      assert {:error, {:live_redirect, %{to: "/admin/verifications", flash: flash}}} =
               live(conn, ~p"/admin/verifications/#{fake_id}")

      assert flash["error"] =~ "not found"
    end

    test "redirects with error flash when id is not a valid UUID", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/admin/verifications", flash: flash}}} =
               live(conn, ~p"/admin/verifications/not-a-uuid")

      assert flash["error"] =~ "not found"
    end

    test "back link navigates to index", %{conn: conn} do
      doc = insert(:verification_document_schema)

      {:ok, view, _html} = live(conn, ~p"/admin/verifications/#{doc.id}")

      assert has_element?(view, "a[href='/admin/verifications']")
    end
  end

  # Approve Flow

  describe "approve flow" do
    setup :register_and_log_in_admin

    test "approve event updates document status", %{conn: conn} do
      doc = insert(:verification_document_schema, status: :pending)

      {:ok, view, _html} = live(conn, ~p"/admin/verifications/#{doc.id}")

      assert has_element?(view, "#approve-button")

      # Click approve (with JS confirm bypass)
      render_click(view, "approve")

      assert_flash(view, :info, "Document approved successfully.")

      # Action buttons should be gone after approval
      refute has_element?(view, "#review-actions")
    end

    test "approve on already-reviewed document shows error flash", %{conn: conn} do
      doc = insert(:approved_verification_document_schema)

      {:ok, view, _html} = live(conn, ~p"/admin/verifications/#{doc.id}")

      # Document is already approved, so no approve button should be shown
      refute has_element?(view, "#approve-button")
    end

    test "approve event on already-approved document returns document_not_pending error", %{
      conn: conn
    } do
      doc = insert(:approved_verification_document_schema)

      {:ok, view, _html} = live(conn, ~p"/admin/verifications/#{doc.id}")

      # Simulate a race condition: send approve event directly even though button isn't rendered
      render_click(view, "approve")

      assert_flash(view, :error, "Document has already been reviewed.")
    end
  end

  # Reject Flow

  describe "reject flow" do
    setup :register_and_log_in_admin

    test "toggle reject form shows the rejection textarea", %{conn: conn} do
      doc = insert(:verification_document_schema, status: :pending)

      {:ok, view, _html} = live(conn, ~p"/admin/verifications/#{doc.id}")

      refute has_element?(view, "#reject-form")

      render_click(view, "toggle_reject_form")

      assert has_element?(view, "#reject-form")
      assert has_element?(view, "#confirm-reject-button")
    end

    test "cancel hides the reject form", %{conn: conn} do
      doc = insert(:verification_document_schema, status: :pending)

      {:ok, view, _html} = live(conn, ~p"/admin/verifications/#{doc.id}")

      # Open the form
      render_click(view, "toggle_reject_form")
      assert has_element?(view, "#reject-form")

      # Cancel (toggle again)
      render_click(view, "toggle_reject_form")
      refute has_element?(view, "#reject-form")
    end

    test "reject with reason updates document and shows flash", %{conn: conn} do
      doc = insert(:verification_document_schema, status: :pending)

      {:ok, view, _html} = live(conn, ~p"/admin/verifications/#{doc.id}")

      # Open reject form
      render_click(view, "toggle_reject_form")

      # Submit rejection
      render_submit(view, "reject", %{
        "rejection" => %{"reason" => "Document expired"}
      })

      assert_flash(view, :info, "Document rejected.")

      # Action buttons should be gone after rejection
      refute has_element?(view, "#review-actions")
    end

    test "reject event on already-approved document returns document_not_pending error", %{
      conn: conn
    } do
      doc = insert(:approved_verification_document_schema)

      {:ok, view, _html} = live(conn, ~p"/admin/verifications/#{doc.id}")

      # Simulate a race condition: send reject event directly even though form isn't rendered
      render_submit(view, "reject", %{
        "rejection" => %{"reason" => "Too late"}
      })

      assert_flash(view, :error, "Document has already been reviewed.")
    end

    test "reject without reason shows error flash", %{conn: conn} do
      doc = insert(:verification_document_schema, status: :pending)

      {:ok, view, _html} = live(conn, ~p"/admin/verifications/#{doc.id}")

      render_click(view, "toggle_reject_form")

      render_submit(view, "reject", %{
        "rejection" => %{"reason" => ""}
      })

      assert_flash(view, :error, "Please provide a rejection reason.")
    end
  end
end
