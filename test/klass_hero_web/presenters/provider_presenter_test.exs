defmodule KlassHeroWeb.Presenters.ProviderPresenterTest do
  use ExUnit.Case, async: true

  alias KlassHero.Provider.ProviderProfile
  alias KlassHeroWeb.Presenters.ProviderPresenter

  describe "verification_status_from_docs/2" do
    # {verified, docs, expected status} — verified always wins; then pending > rejected
    # among doc statuses; all-approved still reads as :pending (awaiting admin sign-off).
    @verification_cases [
      {true, [], :verified},
      {true, [%{status: :pending}], :verified},
      {false, [], :not_started},
      {nil, [], :not_started},
      {false, [%{status: :pending}], :pending},
      {false, [%{status: :rejected}], :rejected},
      {false, [%{status: :approved}], :pending},
      {false, [%{status: :pending}, %{status: :rejected}], :pending},
      {false, [%{status: :approved}, %{status: :rejected}], :rejected}
    ]

    for {verified, docs, expected} <- @verification_cases do
      @verified verified
      @docs docs
      @expected expected
      test "verified=#{inspect(verified)}, docs=#{inspect(docs)} -> #{inspect(expected)}" do
        assert ProviderPresenter.verification_status_from_docs(@verified, @docs) == @expected
      end
    end
  end

  describe "document_type_label/1" do
    # {type, expected label} — every canonical enum clause, in source order.
    @document_type_cases [
      {:business_registration, "Business Registration"},
      {:insurance_certificate, "Insurance Certificate"},
      {:id_document, "ID Document"},
      {:tax_certificate, "Tax Certificate"},
      {:other, "Other"},
      {:experience_validation, "Experience validation"},
      {:background_check, "Background check"},
      {:video_screening, "Video screening"},
      {:safeguarding_certificate, "Safeguarding certificate"},
      # Legacy/out-of-enum values load as the :unknown sentinel (#1026).
      {:unknown, "Unknown"}
    ]

    for {doc_type, expected} <- @document_type_cases do
      @doc_type doc_type
      @expected expected
      test "#{inspect(doc_type)} -> #{inspect(expected)}" do
        assert ProviderPresenter.document_type_label(@doc_type) == @expected
      end
    end

    test "falls back to to_string/1 for an atom outside the known enum" do
      assert ProviderPresenter.document_type_label(:some_future_type) == "some_future_type"
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

    test "carries tagline and cover image through to the view" do
      provider = %ProviderProfile{
        id: "p-b",
        identity_id: "i-b",
        business_name: "Starlight Coaching",
        tagline: "Play-based learning",
        cover_image_url: "https://cdn.example.com/cover.png"
      }

      view = ProviderPresenter.to_public_view(provider)

      assert view.tagline == "Play-based learning"
      assert view.cover_image_url == "https://cdn.example.com/cover.png"
    end

    test "lists only the social networks the provider filled in" do
      provider = %ProviderProfile{
        id: "p-c",
        identity_id: "i-c",
        business_name: "Starlight Coaching",
        instagram_url: "https://instagram.com/starlight",
        youtube_url: "https://youtube.com/@starlight",
        facebook_url: nil,
        tiktok_url: "",
        linkedin_url: nil
      }

      # An empty string is as absent as nil here: a cleared input reaches the
      # column as nil, but a legacy row may still hold "".
      #
      # The leading atom is what `kh_social_icon/1` keys on — asserted explicitly
      # because a glyph lookup keyed on the label string instead would still pass
      # a shape check while breaking the first time a label is edited.
      assert ProviderPresenter.to_public_view(provider).social_links == [
               {:instagram, "Instagram", "https://instagram.com/starlight"},
               {:youtube, "YouTube", "https://youtube.com/@starlight"}
             ]
    end

    test "defaults trust_state to :unverified when none is passed" do
      provider = %ProviderProfile{id: "p-e", identity_id: "i-e", business_name: "Starlight"}

      # Under-claiming is the safe default: kh_trust_mark/1 renders nothing for
      # :unverified, so an unthreaded caller shows no badge rather than a badge
      # the provider has not earned.
      assert ProviderPresenter.to_public_view(provider).trust_state == :unverified
    end

    test "carries the trust state it is given" do
      provider = %ProviderProfile{id: "p-f", identity_id: "i-f", business_name: "Starlight"}

      assert ProviderPresenter.to_public_view(provider, :verified).trust_state == :verified
      assert ProviderPresenter.to_public_view(provider, :in_progress).trust_state == :in_progress
    end

    test "social_links is empty when no network is set" do
      provider = %ProviderProfile{id: "p-d", identity_id: "i-d", business_name: "Starlight"}

      assert ProviderPresenter.to_public_view(provider).social_links == []
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
