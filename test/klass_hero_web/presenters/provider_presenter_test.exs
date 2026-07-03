defmodule KlassHeroWeb.Presenters.ProviderPresenterTest do
  use ExUnit.Case, async: true

  alias KlassHero.Provider.ProviderProfile
  alias KlassHeroWeb.Presenters.ProviderPresenter

  describe "verification_status_from_docs/2" do
    test "returns :verified when provider.verified is true and no docs" do
      assert ProviderPresenter.verification_status_from_docs(true, []) == :verified
    end

    test "returns :verified even when docs are pending" do
      docs = [%{status: :pending}]
      assert ProviderPresenter.verification_status_from_docs(true, docs) == :verified
    end

    test "returns :not_started when no docs submitted" do
      assert ProviderPresenter.verification_status_from_docs(false, []) == :not_started
    end

    test "returns :not_started when verified is nil" do
      assert ProviderPresenter.verification_status_from_docs(nil, []) == :not_started
    end

    test "returns :pending when any doc is pending" do
      docs = [%{status: :pending}]
      assert ProviderPresenter.verification_status_from_docs(false, docs) == :pending
    end

    test "returns :rejected when any doc is rejected" do
      docs = [%{status: :rejected}]
      assert ProviderPresenter.verification_status_from_docs(false, docs) == :rejected
    end

    test "returns :pending when all docs approved (awaiting admin final verification)" do
      docs = [%{status: :approved}]
      assert ProviderPresenter.verification_status_from_docs(false, docs) == :pending
    end

    test "pending takes priority over rejected" do
      docs = [%{status: :pending}, %{status: :rejected}]
      assert ProviderPresenter.verification_status_from_docs(false, docs) == :pending
    end

    test "rejected present among approved" do
      docs = [%{status: :approved}, %{status: :rejected}]
      assert ProviderPresenter.verification_status_from_docs(false, docs) == :rejected
    end
  end

  describe "to_business_view/1" do
    # Provider tiers removed (ADR-0004): no slot/seat limit fields in the view
    test "carries no program-slot or team-seat limit fields" do
      provider = %ProviderProfile{
        id: "p1",
        identity_id: "i1",
        business_name: "Test Biz"
      }

      view = ProviderPresenter.to_business_view(provider)

      assert view.name == "Test Biz"
      refute Map.has_key?(view, :program_slots_total)
      refute Map.has_key?(view, :team_seats_total)
    end
  end

  describe "to_public_view/1" do
    test "maps business_name, description, and logo_url through to the view" do
      provider = %ProviderProfile{
        id: "p-1",
        identity_id: "i-1",
        business_name: "Starlight Coaching",
        description: "Empowering kids through play-based learning.",
        logo_url: "https://cdn.example.com/starlight.png"
      }

      view = ProviderPresenter.to_public_view(provider)

      assert view.id == "p-1"
      assert view.business_name == "Starlight Coaching"
      assert view.description == "Empowering kids through play-based learning."
      assert view.logo_url == "https://cdn.example.com/starlight.png"
    end

    test "derives two-letter initials from a multi-word business name" do
      provider = %ProviderProfile{
        id: "p-2",
        identity_id: "i-2",
        business_name: "Tiger Academy"
      }

      assert ProviderPresenter.to_public_view(provider).initials == "TA"
    end

    test "derives a single-letter initial from a one-word business name" do
      provider = %ProviderProfile{
        id: "p-3",
        identity_id: "i-3",
        business_name: "Starlight"
      }

      assert ProviderPresenter.to_public_view(provider).initials == "S"
    end

    test "passes through nil description and logo_url" do
      provider = %ProviderProfile{
        id: "p-4",
        identity_id: "i-4",
        business_name: "Minimal Biz"
      }

      view = ProviderPresenter.to_public_view(provider)

      assert view.description == nil
      assert view.logo_url == nil
      assert view.initials == "MB"
    end
  end
end
