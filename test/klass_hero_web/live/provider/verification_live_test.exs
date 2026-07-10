defmodule KlassHeroWeb.Provider.VerificationLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias KlassHero.Provider.Adapters.Driving.Events.EventHandlers.VettingVerificationSync
  alias KlassHero.ProviderFixtures

  setup :register_and_log_in_provider

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

  describe "heading hierarchy" do
    test "the checklist title is an h2, not a second h1", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/verification")

      assert has_element?(view, "h2", "Get verified")
      refute has_element?(view, "h1", "Get verified")
    end
  end
end
