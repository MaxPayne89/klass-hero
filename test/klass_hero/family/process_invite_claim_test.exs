defmodule KlassHero.Family.ProcessInviteClaimTest do
  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures

  alias KlassHero.Family
  alias KlassHero.Family.ProcessInviteClaim

  defp valid_attrs(user_id, overrides \\ %{}) do
    Map.merge(
      %{
        invite_id: Ecto.UUID.generate(),
        user_id: user_id,
        program_id: Ecto.UUID.generate(),
        child_first_name: "Emma",
        child_last_name: "Schmidt",
        child_date_of_birth: ~D[2016-03-15],
        school_grade: 3,
        school_name: "Berlin Elementary",
        medical_conditions: "Asthma",
        nut_allergy: true
      },
      overrides
    )
  end

  # The provider collects photo permission in the CSV and it rides the whole way here in the
  # event payload. It used to stop at the handler, which never copied it into the worker's
  # args — so no invite claim ever produced a consent record.
  describe "photo consent from the invite" do
    test "grants each consent the parent agreed to" do
      user = user_fixture()

      attrs =
        valid_attrs(user.id, %{
          consent_photo_marketing: true,
          consent_photo_social_media: true
        })

      assert {:ok, %{child: child}} = ProcessInviteClaim.execute(attrs)

      assert Family.child_has_active_consent?(child.id, "photo_marketing")
      assert Family.child_has_active_consent?(child.id, "photo_social_media")
    end

    test "records nothing for a consent the parent declined" do
      user = user_fixture()

      attrs =
        valid_attrs(user.id, %{
          consent_photo_marketing: true,
          consent_photo_social_media: false
        })

      assert {:ok, %{child: child}} = ProcessInviteClaim.execute(attrs)

      assert Family.child_has_active_consent?(child.id, "photo_marketing")
      refute Family.child_has_active_consent?(child.id, "photo_social_media")
    end

    # The worker retries, and a second program's invite reuses the same child, so the grant
    # runs again against a consent that already exists. `grant_consent/1` catches that
    # constraint inside the enclosing transaction, which is why it needs `mode: :savepoint` —
    # without it the violation aborts the whole transaction rather than being caught (#1065).
    test "a replay grants no duplicates and does not poison the transaction" do
      user = user_fixture()
      attrs = valid_attrs(user.id, %{consent_photo_marketing: true})

      assert {:ok, %{child: child}} = ProcessInviteClaim.execute(attrs)
      assert {:ok, %{child: same_child}} = ProcessInviteClaim.execute(attrs)

      assert same_child.id == child.id
      assert Family.child_has_active_consent?(child.id, "photo_marketing")
    end
  end

  describe "execute/1" do
    test "creates parent profile and child for new user" do
      user = user_fixture()
      attrs = valid_attrs(user.id)

      assert {:ok, %{child: child, parent: parent}} = ProcessInviteClaim.execute(attrs)

      assert child.first_name == "Emma"
      assert child.last_name == "Schmidt"
      assert child.date_of_birth == ~D[2016-03-15]
      assert child.school_grade == 3
      assert child.school_name == "Berlin Elementary"
      assert child.support_needs == "Asthma"
      assert child.allergies == "Nut allergy"
      assert Family.child_belongs_to_parent?(child.id, parent.id)
    end

    test "reuses existing parent profile" do
      user = user_fixture()
      {:ok, existing_parent} = Family.create_parent_profile(%{identity_id: user.id})
      attrs = valid_attrs(user.id)

      assert {:ok, %{parent: parent}} = ProcessInviteClaim.execute(attrs)
      assert parent.id == existing_parent.id
    end

    test "reuses existing child with same name and DOB (idempotent)" do
      user = user_fixture()
      attrs = valid_attrs(user.id)

      assert {:ok, %{child: first_child}} = ProcessInviteClaim.execute(attrs)

      # Second call with different program but same child data
      attrs2 =
        valid_attrs(user.id, %{
          invite_id: Ecto.UUID.generate(),
          program_id: Ecto.UUID.generate()
        })

      assert {:ok, %{child: second_child}} = ProcessInviteClaim.execute(attrs2)
      assert second_child.id == first_child.id

      # Only one child exists for this parent
      {:ok, parent} = Family.get_parent_by_identity(user.id)
      assert length(Family.get_children(parent.id)) == 1
    end

    test "creates separate children when names differ" do
      user = user_fixture()
      attrs1 = valid_attrs(user.id)

      attrs2 =
        valid_attrs(user.id, %{
          invite_id: Ecto.UUID.generate(),
          program_id: Ecto.UUID.generate(),
          child_first_name: "Liam",
          child_date_of_birth: ~D[2018-07-01]
        })

      assert {:ok, %{child: child1}} = ProcessInviteClaim.execute(attrs1)
      assert {:ok, %{child: child2}} = ProcessInviteClaim.execute(attrs2)
      assert child1.id != child2.id
    end

    test "deduplicates children case-insensitively" do
      user = user_fixture()
      attrs = valid_attrs(user.id)

      assert {:ok, %{child: first_child}} = ProcessInviteClaim.execute(attrs)

      # Same child with different casing
      attrs2 =
        valid_attrs(user.id, %{
          invite_id: Ecto.UUID.generate(),
          program_id: Ecto.UUID.generate(),
          child_first_name: "emma",
          child_last_name: "schmidt"
        })

      assert {:ok, %{child: second_child}} = ProcessInviteClaim.execute(attrs2)
      assert second_child.id == first_child.id

      {:ok, parent} = Family.get_parent_by_identity(user.id)
      assert length(Family.get_children(parent.id)) == 1
    end

    test "does not false-match when date_of_birth is nil" do
      user = user_fixture()
      attrs = valid_attrs(user.id)

      assert {:ok, %{child: _first_child}} = ProcessInviteClaim.execute(attrs)

      # Same name but nil DOB — should not match existing child
      attrs2 =
        valid_attrs(user.id, %{
          invite_id: Ecto.UUID.generate(),
          program_id: Ecto.UUID.generate(),
          child_date_of_birth: nil
        })

      # Trigger: nil DOB skips dedup, falls through to domain validation which rejects it
      assert {:error, _reason} = ProcessInviteClaim.execute(attrs2)

      {:ok, parent} = Family.get_parent_by_identity(user.id)
      assert length(Family.get_children(parent.id)) == 1
    end

    test "idempotent retry after partial commit (event dispatch failure recovery)" do
      user = user_fixture()
      attrs = valid_attrs(user.id)

      # First execution: creates parent + child, dispatches event
      assert {:ok, %{child: first_child, parent: first_parent}} =
               ProcessInviteClaim.execute(attrs)

      # Simulate retry scenario: if event dispatch had failed on the first call,
      # Oban would retry with the same args. The retry must find existing parent
      # and child (idempotent) and succeed.
      assert {:ok, %{child: retry_child, parent: retry_parent}} =
               ProcessInviteClaim.execute(attrs)

      # Same records reused -- no duplicates created
      assert retry_parent.id == first_parent.id
      assert retry_child.id == first_child.id

      # Only one child exists for this parent
      {:ok, parent} = Family.get_parent_by_identity(user.id)
      assert length(Family.get_children(parent.id)) == 1
    end

    test "maps nut_allergy false to nil allergies" do
      user = user_fixture()
      attrs = valid_attrs(user.id, %{nut_allergy: false})

      assert {:ok, %{child: child}} = ProcessInviteClaim.execute(attrs)
      assert is_nil(child.allergies)
    end

    test "handles nil optional fields" do
      user = user_fixture()

      attrs =
        valid_attrs(user.id, %{
          school_grade: nil,
          school_name: nil,
          medical_conditions: nil,
          nut_allergy: false
        })

      assert {:ok, %{child: child}} = ProcessInviteClaim.execute(attrs)
      assert is_nil(child.school_grade)
      assert is_nil(child.school_name)
      assert is_nil(child.support_needs)
      assert is_nil(child.allergies)
    end
  end
end
