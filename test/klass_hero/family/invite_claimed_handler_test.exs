defmodule KlassHero.Family.InviteClaimedHandlerTest do
  @moduledoc """
  Tests for InviteClaimedHandler -- enqueues Oban job for invite processing.

  Oban is `testing: :inline` in test env, so jobs execute synchronously.
  We verify end-to-end outcomes (parent + child created).
  """

  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures

  alias KlassHero.Family
  alias KlassHero.Family.InviteClaimedHandler
  alias KlassHero.Shared.Domain.Events.Event

  defp build_invite_claimed_event(attrs) do
    invite_id = Map.get(attrs, :invite_id, Ecto.UUID.generate())
    user_id = Map.get(attrs, :user_id, Ecto.UUID.generate())
    program_id = Map.get(attrs, :program_id, Ecto.UUID.generate())
    provider_id = Map.get(attrs, :provider_id, Ecto.UUID.generate())

    payload =
      Map.merge(
        %{
          invite_id: invite_id,
          user_id: user_id,
          program_id: program_id,
          provider_id: provider_id,
          child_first_name: "Emma",
          child_last_name: "Schmidt",
          child_date_of_birth: ~D[2016-03-15],
          guardian_email: "parent@example.com",
          school_grade: 3,
          school_name: "Berlin Elementary",
          medical_conditions: "Asthma",
          nut_allergy: true,
          consent_photo_marketing: false,
          consent_photo_social_media: false
        },
        attrs
      )

    Event.new(
      :invite_claimed,
      :enrollment,
      :invite,
      invite_id,
      payload
    )
  end

  describe "subscribed_events/0" do
    test "subscribes to :invite_claimed" do
      assert :invite_claimed in InviteClaimedHandler.subscribed_events()
    end
  end

  describe "handle_event/1" do
    test "enqueues job that creates parent profile and child" do
      user = user_fixture()
      event = build_invite_claimed_event(%{user_id: user.id})

      assert :ok = InviteClaimedHandler.handle_event(event)

      {:ok, parent} = Family.get_parent_by_identity(user.id)
      children = Family.get_children(parent.id)
      assert length(children) == 1
      child = hd(children)
      assert child.first_name == "Emma"
      assert child.last_name == "Schmidt"
      assert child.date_of_birth == ~D[2016-03-15]
      assert child.school_grade == 3
      assert child.school_name == "Berlin Elementary"
      assert child.support_needs == "Asthma"
      assert child.allergies == "Nut allergy"
    end

    test "maps nut_allergy false to nil allergies" do
      user = user_fixture()
      event = build_invite_claimed_event(%{user_id: user.id, nut_allergy: false})

      assert :ok = InviteClaimedHandler.handle_event(event)

      {:ok, parent} = Family.get_parent_by_identity(user.id)
      child = hd(Family.get_children(parent.id))
      assert is_nil(child.allergies)
    end

    test "handles nil optional fields gracefully" do
      user = user_fixture()

      event =
        build_invite_claimed_event(%{
          user_id: user.id,
          school_grade: nil,
          school_name: nil,
          medical_conditions: nil,
          nut_allergy: false
        })

      assert :ok = InviteClaimedHandler.handle_event(event)

      {:ok, parent} = Family.get_parent_by_identity(user.id)
      child = hd(Family.get_children(parent.id))
      assert is_nil(child.school_grade)
      assert is_nil(child.school_name)
      assert is_nil(child.support_needs)
      assert is_nil(child.allergies)
    end

    test "is idempotent when parent profile already exists" do
      user = user_fixture()
      {:ok, _parent} = Family.create_parent_profile(%{identity_id: user.id})

      event = build_invite_claimed_event(%{user_id: user.id})
      assert :ok = InviteClaimedHandler.handle_event(event)

      {:ok, parent} = Family.get_parent_by_identity(user.id)
      children = Family.get_children(parent.id)
      assert length(children) == 1
    end

    test "ignores unrelated events" do
      event = Event.new(:something_else, :other, :thing, "id", %{})
      assert :ignore = InviteClaimedHandler.handle_event(event)
    end
  end
end
