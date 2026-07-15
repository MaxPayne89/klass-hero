defmodule KlassHeroWeb.Provider.VerificationLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias KlassHero.Accounts.Scope
  alias KlassHero.AccountsFixtures
  alias KlassHero.Factory
  alias KlassHero.Provider
  alias KlassHero.Provider.Adapters.Driving.Events.EventHandlers.VettingVerificationSync
  alias KlassHero.ProviderFixtures

  setup :register_and_log_in_provider

  # Logs in a fresh *business* provider, overriding the module-level individual setup for the
  # business-track describe block below.
  defp log_in_business_provider(%{conn: conn}) do
    user = AccountsFixtures.user_fixture(%{intended_roles: [:provider]})
    provider = Factory.insert(:provider_profile_schema, identity_id: user.id, entity_type: :business)
    scope = Scope.for_user(user) |> Scope.resolve_roles()
    %{conn: log_in_user(conn, user), user: user, scope: scope, provider: provider}
  end

  describe "onboarding checklist" do
    test "renders all individual-track steps in order", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/verification")

      for key <- [:identity, :experience, :background, :video, :safeguarding, :community_agreement] do
        assert has_element?(view, "#vetting-step-#{key}")
      end
    end

    test "shows the profile-locked banner with progress until verified", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/verification")

      assert has_element?(view, "#vetting-locked-banner", "0 of 6")
    end

    test "a rejected document step shows its reason and a resubmit action", %{conn: conn, provider: provider} do
      reviewer = KlassHero.AccountsFixtures.user_fixture()

      ProviderFixtures.rejected_verification_document_fixture(%{
        provider_id: provider.id,
        document_type: "experience_validation",
        rejection_reason: "Blurry scan — please re-upload.",
        reviewer_id: reviewer.id
      })

      {:ok, view, _html} = live(conn, ~p"/provider/verification")

      assert has_element?(view, "#vetting-step-experience", "Blurry scan")
      assert has_element?(view, "#vetting-action-experience[href*='verification-docs']")
    end

    test "the experience step links to the in-page upload panel when not started", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/verification")

      assert has_element?(view, "#vetting-action-experience[href*='verification-docs']")
    end

    test "a verification-updated signal flips a step's status live", %{conn: conn, provider: provider} do
      reviewer = KlassHero.AccountsFixtures.user_fixture()

      {:ok, view, _html} = live(conn, ~p"/provider/verification")
      refute has_element?(view, "#vetting-step-experience", "Blurry scan")

      # Mirror the review handler: the rejected document exists in the DB before the signal fires.
      ProviderFixtures.rejected_verification_document_fixture(%{
        provider_id: provider.id,
        document_type: "experience_validation",
        rejection_reason: "Blurry scan — please re-upload.",
        reviewer_id: reviewer.id
      })

      send(view.pid, :verification_updated)

      assert has_element?(view, "#vetting-step-experience", "Blurry scan")
    end
  end

  describe "identity widget — not started" do
    test "renders the start-verification button when no identity verification exists", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/verification")

      assert has_element?(view, "#identity-verify-start")
      # The individual track gets the bare button, never the business responsible-person or
      # registration forms.
      refute has_element?(view, "#responsible-person-form")
      refute has_element?(view, "#business-registration-form")
    end

    test "shows a duration hint so the lone CTA card has supporting context", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/verification")

      assert has_element?(view, "#identity-verify-not-started", "minute")
    end
  end

  describe "identity widget — read state" do
    test "renders in-progress for a processing session", %{conn: conn, provider: provider} do
      ProviderFixtures.identity_verification_fixture(provider_id: provider.id, status: :processing)

      {:ok, view, _html} = live(conn, ~p"/provider/verification")

      assert has_element?(view, "#identity-verify-in-progress")
      refute has_element?(view, "#identity-verify-start")
    end

    test "renders approved for a passed verification", %{conn: conn, provider: provider} do
      ProviderFixtures.identity_verification_fixture(provider_id: provider.id, status: :verified, outcome: :pass)

      {:ok, view, _html} = live(conn, ~p"/provider/verification")

      assert has_element?(view, "#identity-verify-approved")
    end

    test "renders failed with a retry button for a failed verification", %{conn: conn, provider: provider} do
      ProviderFixtures.identity_verification_fixture(
        provider_id: provider.id,
        status: :verified,
        outcome: :fail,
        failure_reason: "under_18"
      )

      {:ok, view, _html} = live(conn, ~p"/provider/verification")

      assert has_element?(view, "#identity-verify-failed")
      assert has_element?(view, "#identity-verify-retry")
      # under_18 is terminal — copy says so rather than implying a retry will help.
      assert has_element?(view, "#identity-verify-failed", "18 and over")
    end
  end

  describe "provider-scoped live refresh" do
    test "re-fetches on this provider's topic but not another provider's", %{conn: conn, provider: provider} do
      iv = ProviderFixtures.identity_verification_fixture(provider_id: provider.id, status: :processing)

      {:ok, view, _html} = live(conn, ~p"/provider/verification")
      assert has_element?(view, "#identity-verify-in-progress")

      # Truth becomes a pass (mirrors the webhook writing before the broadcast).
      _ = iv

      ProviderFixtures.identity_verification_fixture(provider_id: provider.id, status: :verified, outcome: :pass)

      # A broadcast on a DIFFERENT provider's topic must not touch this view.
      VettingVerificationSync.broadcast_updated(Ecto.UUID.generate())
      assert has_element?(view, "#identity-verify-in-progress")
      refute has_element?(view, "#identity-verify-approved")

      # This provider's topic triggers the re-fetch.
      VettingVerificationSync.broadcast_updated(provider.id)
      assert has_element?(view, "#identity-verify-approved")
    end
  end

  describe "document upload (self-contained panel)" do
    test "uploading a document streams it into the panel", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/verification")

      entry =
        file_input(view, "#doc-upload-form", :verification_doc, [
          %{name: "experience.pdf", content: "pdf-bytes", type: "application/pdf"}
        ])

      render_upload(entry, "experience.pdf")
      view |> form("#doc-upload-form") |> render_submit()

      assert has_element?(view, "#verification-docs", "experience.pdf")
    end

    test "the individual track offers the dedicated video uploader", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/verification")

      assert has_element?(view, "#video-upload-form")

      entry =
        file_input(view, "#video-upload-form", :verification_video, [
          %{name: "screening.mp4", content: "video-bytes", type: "video/mp4"}
        ])

      render_upload(entry, "screening.mp4")
      view |> form("#video-upload-form") |> render_submit()

      assert has_element?(view, "#verification-docs", "screening.mp4")
    end
  end

  describe "community standards agreement" do
    test "renders the guidelines, PDF link and agreement form for an individual provider", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/verification")

      assert has_element?(view, "#community-agreement-form")
      assert has_element?(view, "#community-guidelines")
      assert has_element?(view, "#submit-agreement-btn")

      assert has_element?(
               view,
               ~s(a[href="/downloads/Klass_Hero_Community_Standards_Agreement_v1.0.pdf"])
             )
    end

    test "the community-agreement checklist action anchors to the in-page form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/verification")

      assert has_element?(view, "#vetting-action-community_agreement[href*='community-agreement-form']")
    end

    test "submitting with the box checked records the agreement and shows the signed confirmation", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/verification")

      view
      |> form("#community-agreement-form", %{agreement: %{agree: "true"}})
      |> render_submit()

      assert render(view) =~ "You have agreed to the Community Guidelines"
      refute has_element?(view, "#community-agreement-form")
    end

    test "submitting without checking the box does not record agreement", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/verification")

      view
      |> form("#community-agreement-form", %{agreement: %{agree: "false"}})
      |> render_submit()

      assert has_element?(view, "#community-agreement-form")
      refute render(view) =~ "You have agreed to the Community Guidelines"
    end
  end

  describe "community standards agreement (business track)" do
    setup :log_in_business_provider

    test "shows the responsible person as the signer on the panel", %{conn: conn, provider: provider} do
      {:ok, :set} = Provider.set_responsible_person(provider.id, "Jane Smith", "Owner")

      {:ok, view, _html} = live(conn, ~p"/provider/verification")

      assert has_element?(view, "#agreement-signer", "Jane Smith")
    end

    test "signing records the responsible person, not the logged-in user, as the signatory",
         %{conn: conn, provider: provider} do
      {:ok, :set} = Provider.set_responsible_person(provider.id, "Jane Smith", "Owner")
      {:ok, view, _html} = live(conn, ~p"/provider/verification")

      view
      |> form("#community-agreement-form", %{agreement: %{agree: "true"}})
      |> render_submit()

      agreement = Provider.get_latest_community_agreement(provider.id)
      assert agreement.signed_by_name == "Jane Smith"
      assert agreement.entity_type == :business
    end
  end

  describe "staff compliance declaration (business track)" do
    setup :log_in_business_provider

    test "renders the provisional declaration and attestation form for a business", %{conn: conn, provider: provider} do
      {:ok, :set} = Provider.set_responsible_person(provider.id, "Jane Smith", "Owner")

      {:ok, view, _html} = live(conn, ~p"/provider/verification")

      assert has_element?(view, "#staff-attestation-form")
      assert has_element?(view, "#staff-attestation-declaration")
      assert has_element?(view, "#submit-attestation-btn")
      assert render(view) =~ "Provisional text"
    end

    test "each agreement checklist action anchors to its own in-page form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/verification")

      assert has_element?(view, "#vetting-action-community_agreement[href*='community-agreement-form']")
      assert has_element?(view, "#vetting-action-staff_attestation[href*='staff-attestation-form']")
    end

    test "shows the responsible person as the signer on the panel", %{conn: conn, provider: provider} do
      {:ok, :set} = Provider.set_responsible_person(provider.id, "Jane Smith", "Owner")

      {:ok, view, _html} = live(conn, ~p"/provider/verification")

      assert has_element?(view, "#attestation-signer", "Jane Smith")
    end

    test "signing records the responsible person and stamps the staff-attestation kind + :business",
         %{conn: conn, provider: provider} do
      {:ok, :set} = Provider.set_responsible_person(provider.id, "Jane Smith", "Owner")
      {:ok, view, _html} = live(conn, ~p"/provider/verification")

      view
      |> form("#staff-attestation-form", %{attestation: %{agree: "true"}})
      |> render_submit()

      attestation = Provider.get_latest_staff_attestation(provider.id)
      assert attestation.kind == :staff_attestation
      assert attestation.signed_by_name == "Jane Smith"
      assert attestation.entity_type == :business
      assert render(view) =~ "You have signed the Staff Compliance Declaration"
    end
  end

  describe "responsible person (business track)" do
    setup :log_in_business_provider

    test "renders the responsible-person form in place of the bare identity button", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/verification")

      assert has_element?(view, "#vetting-step-responsible_person_identity")
      assert has_element?(view, "#responsible-person-form")
      assert has_element?(view, "#responsible-person-start")
      refute has_element?(view, "#identity-verify-start")
    end

    test "pre-fills the form with a previously set responsible person", %{conn: conn, provider: provider} do
      {:ok, :set} = Provider.set_responsible_person(provider.id, "Jane Smith", "Owner")

      {:ok, view, _html} = live(conn, ~p"/provider/verification")

      assert has_element?(view, "#responsible-person-form input[value='Jane Smith']")
      assert has_element?(view, "#responsible-person-form input[value='Owner']")
    end
  end

  describe "business registration (business track)" do
    setup :log_in_business_provider

    test "renders the dedicated registration form with a country selector, in place of the generic upload",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/verification")

      assert has_element?(view, "#vetting-step-business_registration")
      assert has_element?(view, "#business-registration-form")
      assert has_element?(view, "#business-registration-form select")
      assert has_element?(view, "#business-registration-submit")

      # The business_registration step is submitted only via the dedicated widget, so the
      # generic document panel must not also offer it.
      refute has_element?(view, "#doc-type-select option[value='business_registration']")
    end

    test "submitting the form with a file records the document and flips the step to review",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/verification")

      entry =
        file_input(view, "#business-registration-form", :business_registration_doc, [
          %{name: "registration.pdf", content: "pdf-bytes", type: "application/pdf"}
        ])

      render_upload(entry, "registration.pdf")

      view
      |> form("#business-registration-form", %{
        business_registration: %{
          registration_country: "DE",
          legal_business_name: "Acme Kids GmbH",
          registration_number: "HRB 12345"
        }
      })
      |> render_submit()

      assert has_element?(view, "#vetting-step-business_registration", "Under review")
    end

    test "pre-fills the form with previously submitted registration details", %{conn: conn, provider: provider} do
      {:ok, _doc} =
        Provider.submit_business_registration(provider.id, %{
          legal_business_name: "Acme Kids GmbH",
          registration_number: "HRB 12345",
          registration_country: "DE",
          file_binary: "pdf-bytes",
          original_filename: "registration.pdf",
          content_type: "application/pdf"
        })

      {:ok, view, _html} = live(conn, ~p"/provider/verification")

      assert has_element?(view, "#business-registration-form input[value='Acme Kids GmbH']")
      assert has_element?(view, "#business-registration-form input[value='HRB 12345']")
    end
  end

  describe "insurance (business track)" do
    setup :log_in_business_provider

    test "renders the dedicated insurance form with an expiry date input, not the generic upload",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/verification")

      assert has_element?(view, "#vetting-step-insurance")
      assert has_element?(view, "#insurance-form")
      assert has_element?(view, "#insurance-form input[type='date']")
      assert has_element?(view, "#insurance-submit")

      # Insurance is submitted only via the dedicated widget, so the generic panel must not offer it.
      refute has_element?(view, "#doc-type-select option[value='insurance_certificate']")
    end

    test "submitting with a file and expiry date records the document and flips the step to review",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/verification")

      entry =
        file_input(view, "#insurance-form", :insurance_doc, [
          %{name: "insurance.pdf", content: "pdf-bytes", type: "application/pdf"}
        ])

      render_upload(entry, "insurance.pdf")

      view
      |> form("#insurance-form", %{insurance: %{expiry_date: "2027-01-01"}})
      |> render_submit()

      assert has_element?(view, "#vetting-step-insurance", "Under review")
    end

    test "shows a live expired warning when the typed date is in the past", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/verification")

      past = Date.utc_today() |> Date.add(-1) |> Date.to_iso8601()

      view
      |> form("#insurance-form", %{insurance: %{expiry_date: past}})
      |> render_change()

      assert has_element?(view, "#insurance-expiry-warning", "expired")
    end

    test "shows a live expiring-soon warning when the typed date is within 30 days", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/verification")

      soon = Date.utc_today() |> Date.add(10) |> Date.to_iso8601()

      view
      |> form("#insurance-form", %{insurance: %{expiry_date: soon}})
      |> render_change()

      assert has_element?(view, "#insurance-expiry-warning", "30 days")
    end
  end

  describe "heading hierarchy" do
    test "the checklist title is an h2, not a second h1", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/verification")

      assert has_element?(view, "h2", "Get verified")
      refute has_element?(view, "h1", "Get verified")
    end
  end
end
