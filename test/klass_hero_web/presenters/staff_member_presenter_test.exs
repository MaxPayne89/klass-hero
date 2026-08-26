defmodule KlassHeroWeb.Presenters.StaffMemberPresenterTest do
  @moduledoc """
  Security-critical tests — the base `to_card_view/1` is consumed by the parent-facing
  program detail page. Pay rates MUST NEVER leak through that function. Admin and
  self-view variants may include the rate because they are gated to business owners
  and the staff member themselves.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias KlassHero.Provider.{PayRate, StaffMember}
  alias KlassHeroWeb.Presenters.StaffMemberPresenter

  defp staff_fixture(overrides) do
    struct!(
      StaffMember,
      Map.merge(
        %{
          id: Ecto.UUID.generate(),
          provider_id: Ecto.UUID.generate(),
          first_name: "Mike",
          last_name: "Johnson",
          role: "Head Coach",
          email: "mike@example.com",
          bio: "Experienced coach.",
          tags: [],
          qualifications: [],
          active: true,
          invitation_status: :accepted
        },
        overrides
      )
    )
  end

  defp hourly_rate do
    {:ok, rate} = PayRate.hourly(Decimal.new("25.00"))
    rate
  end

  defp per_session_rate do
    {:ok, rate} = PayRate.per_session(Decimal.new("80.00"))
    rate
  end

  # An arbitrary staff member with random identity fields and any pay-rate state.
  # Used to assert the parent-facing leak invariant holds for ALL inputs, not
  # just the two hand-picked examples.
  defp staff_generator do
    gen all(
          first <- StreamData.string(:alphanumeric, min_length: 1, max_length: 12),
          last <- StreamData.string(:alphanumeric, min_length: 1, max_length: 12),
          pay_rate <- StreamData.member_of([nil, hourly_rate(), per_session_rate()])
        ) do
      staff_fixture(%{first_name: first, last_name: last, pay_rate: pay_rate})
    end
  end

  describe "to_card_view/1 — parent/public-facing (no pay_rate)" do
    test "never includes pay_rate, even when the StaffMember has one set" do
      staff = staff_fixture(%{pay_rate: hourly_rate()})

      view = StaffMemberPresenter.to_card_view(staff)

      refute Map.has_key?(view, :pay_rate)
      refute Map.has_key?(view, :rate_label)
    end

    test "renders a leak-free view when the StaffMember has no pay_rate" do
      staff = staff_fixture(%{pay_rate: nil})

      view = StaffMemberPresenter.to_card_view(staff)

      refute Map.has_key?(view, :pay_rate)
      assert view.full_name == "Mike Johnson"
    end

    # `user_id` is an internal Accounts identifier and `can_message?` is an
    # owner-only affordance. Both belong to the admin view. Pinned here because
    # nothing else does: no assertion in this file pins the key set, so when they
    # were first added to the base view (#747) the whole suite stayed green.
    test "carries neither :user_id nor the owner-only :can_message? affordance" do
      staff = staff_fixture(%{user_id: Ecto.UUID.generate()})

      view = StaffMemberPresenter.to_card_view(staff)

      refute Map.has_key?(view, :user_id)
      refute Map.has_key?(view, :can_message?)
    end

    # Security invariant: no matter the staff member's fields or pay-rate state,
    # the parent-facing card must never carry compensation data.
    property "never leaks :pay_rate or :rate_label for any staff member" do
      check all(staff <- staff_generator()) do
        view = StaffMemberPresenter.to_card_view(staff)

        refute Map.has_key?(view, :pay_rate)
        refute Map.has_key?(view, :rate_label)
      end
    end
  end

  describe "to_card_view_list/1" do
    test "maps a list without leaking pay_rate" do
      list = [staff_fixture(%{pay_rate: hourly_rate()}), staff_fixture(%{pay_rate: nil})]

      views = StaffMemberPresenter.to_card_view_list(list)

      for view <- views do
        refute Map.has_key?(view, :pay_rate)
      end
    end

    property "never leaks pay data for any list of staff members" do
      check all(staff_list <- StreamData.list_of(staff_generator(), max_length: 5)) do
        views = StaffMemberPresenter.to_card_view_list(staff_list)

        assert Enum.all?(views, &(not Map.has_key?(&1, :pay_rate)))
        assert Enum.all?(views, &(not Map.has_key?(&1, :rate_label)))
      end
    end
  end

  describe "to_hero_card/1 — parent/public-facing hero card (badge always nil)" do
    test "uses hero-card-staff DOM id prefix" do
      staff = staff_fixture(%{})

      card = StaffMemberPresenter.to_hero_card(staff)

      assert card.id == "hero-card-staff-#{staff.id}"
    end

    test "exposes :name (not :full_name) as the display name" do
      staff = staff_fixture(%{first_name: "Alice", last_name: "Smith"})

      card = StaffMemberPresenter.to_hero_card(staff)

      assert card.name == "Alice Smith"
      refute Map.has_key?(card, :full_name)
    end

    test "badge is always nil — badge is applied only by HeroCardsPresenter" do
      staff = staff_fixture(%{})

      card = StaffMemberPresenter.to_hero_card(staff)

      assert is_nil(card.badge)
    end

    test "nil tags and qualifications default to empty lists" do
      staff = staff_fixture(%{tags: nil, qualifications: nil})

      card = StaffMemberPresenter.to_hero_card(staff)

      assert card.tags == []
      assert card.qualifications == []
    end
  end

  describe "to_hero_card_list/1" do
    test "maps a list preserving badge: nil on each card" do
      list = [
        staff_fixture(%{first_name: "Alice", last_name: "A"}),
        staff_fixture(%{first_name: "Bob", last_name: "B"})
      ]

      cards = StaffMemberPresenter.to_hero_card_list(list)

      assert length(cards) == 2
      assert Enum.map(cards, & &1.name) == ["Alice A", "Bob B"]
      assert Enum.all?(cards, &is_nil(&1.badge))
    end
  end

  describe "to_admin_view/1 — business-owner-facing (includes pay_rate)" do
    test "includes a formatted rate_label when pay_rate is hourly" do
      staff = staff_fixture(%{pay_rate: hourly_rate()})

      view = StaffMemberPresenter.to_admin_view(staff)

      assert view.pay_rate.type == :hourly
      assert view.rate_label == "€25.00 / hour"
    end

    test "includes a formatted rate_label when pay_rate is per_session" do
      {:ok, rate} = PayRate.per_session(Decimal.new("80.00"))
      staff = staff_fixture(%{pay_rate: rate})

      view = StaffMemberPresenter.to_admin_view(staff)

      assert view.rate_label == "€80.00 / session"
    end

    test "returns nil rate_label when pay_rate is nil" do
      staff = staff_fixture(%{pay_rate: nil})

      view = StaffMemberPresenter.to_admin_view(staff)

      assert is_nil(view.pay_rate)
      assert is_nil(view.rate_label)
    end

    # The Team tab's Message action reads both. `can_message?` tracks whether the
    # member has claimed their invite — an invited-but-unclaimed member has no
    # account to write to.
    test "carries :user_id and :can_message? for a member who has claimed their invite" do
      user_id = Ecto.UUID.generate()

      view = StaffMemberPresenter.to_admin_view(staff_fixture(%{user_id: user_id}))

      assert view.user_id == user_id
      assert view.can_message?
    end

    test "reports can_message? false for a member who has not claimed their invite" do
      view = StaffMemberPresenter.to_admin_view(staff_fixture(%{user_id: nil}))

      assert is_nil(view.user_id)
      refute view.can_message?
    end
  end

  describe "to_self_view/1 — staff-member-facing (includes own pay_rate)" do
    test "includes the staff's own pay rate" do
      staff = staff_fixture(%{pay_rate: hourly_rate()})

      view = StaffMemberPresenter.to_self_view(staff)

      assert view.pay_rate.type == :hourly
      assert view.rate_label == "€25.00 / hour"
    end

    test "returns nil rate_label when no pay_rate is set" do
      staff = staff_fixture(%{pay_rate: nil})

      view = StaffMemberPresenter.to_self_view(staff)

      assert is_nil(view.pay_rate)
      assert is_nil(view.rate_label)
    end
  end
end
