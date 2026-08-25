defmodule KlassHero.Family.ChildrenTest do
  @moduledoc """
  Context tests for child CRUD and queries through the `KlassHero.Family`
  public API, exercised against the real sandbox database.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Family
  alias KlassHero.Family.Child
  alias KlassHero.Family.ChildGuardian
  alias KlassHero.Family.Consent

  @valid_attrs %{
    first_name: "Emma",
    last_name: "Smith",
    date_of_birth: ~D[2015-06-15]
  }

  defp parent, do: insert(:parent_profile_schema)

  describe "create_child/1" do
    test "creates a child and returns the persisted struct" do
      attrs = Map.merge(@valid_attrs, %{emergency_contact: "555-1234", allergies: "Peanuts"})

      assert {:ok, %Child{} = child} = Family.create_child(attrs)
      assert {:ok, _} = Ecto.UUID.dump(child.id)
      assert child.first_name == "Emma"
      assert child.allergies == "Peanuts"
      assert %DateTime{} = child.inserted_at
    end

    test "autogenerates a UUID id" do
      assert {:ok, child} = Family.create_child(@valid_attrs)
      assert byte_size(child.id) == 36
    end

    test "links a guardian when :parent_id is given" do
      parent = parent()

      assert {:ok, %Child{} = child} = Family.create_child(Map.put(@valid_attrs, :parent_id, parent.id))

      link = Repo.get_by!(ChildGuardian, child_id: child.id, guardian_id: parent.id)
      assert link.relationship == "parent"
      assert link.is_primary == true
    end

    test "returns a changeset error for a future date of birth" do
      attrs = %{@valid_attrs | date_of_birth: Date.add(Date.utc_today(), 30)}
      assert {:error, %Ecto.Changeset{}} = Family.create_child(attrs)
    end

    test "returns a changeset error for a blank first name" do
      assert {:error, %Ecto.Changeset{}} = Family.create_child(%{@valid_attrs | first_name: ""})
    end

    test "rolls back the child when the guardian link fails" do
      count_before = Repo.aggregate(Child, :count)

      assert {:error, %Ecto.Changeset{}} =
               Family.create_child(Map.put(@valid_attrs, :parent_id, Ecto.UUID.generate()))

      assert Repo.aggregate(Child, :count) == count_before
    end
  end

  # #1322 lost a guardian's consent because ChildrenLive persisted the child and then
  # granted the consent as a separate top-level call. These cover the fold-in: the two
  # writes now share one transaction, so neither can survive the other's failure.
  describe "create_child/2 with consents" do
    @consent_type "provider_data_sharing"

    test "writes the child and its consent in one call" do
      parent = parent()
      attrs = Map.put(@valid_attrs, :parent_id, parent.id)

      assert {:ok, %Child{} = child} =
               Family.create_child(attrs, consents: %{@consent_type => true})

      assert Family.child_has_active_consent?(child.id, @consent_type)
    end

    # The test that would have caught #1322: a failing consent write must take the
    # child row with it, so there is no half-saved form to remediate later.
    test "rolls back the child when the consent write fails" do
      parent = parent()
      attrs = Map.put(@valid_attrs, :parent_id, parent.id)
      count_before = Repo.aggregate(Child, :count)

      assert {:error, {:consent, %Ecto.Changeset{}}} =
               Family.create_child(attrs, consents: %{"" => true})

      assert Repo.aggregate(Child, :count) == count_before
    end

    test "grants nothing when consent is not requested" do
      parent = parent()
      attrs = Map.put(@valid_attrs, :parent_id, parent.id)

      assert {:ok, child} = Family.create_child(attrs, consents: %{@consent_type => false})

      refute Family.child_has_active_consent?(child.id, @consent_type)
    end

    test "grants nothing when no consents are passed at all" do
      parent = parent()
      attrs = Map.put(@valid_attrs, :parent_id, parent.id)

      assert {:ok, child} = Family.create_child(attrs)

      refute Family.child_has_active_consent?(child.id, @consent_type)
    end
  end

  describe "update_child/3 with consents" do
    setup do
      parent = parent()

      {:ok, child} = Family.create_child(Map.put(@valid_attrs, :parent_id, parent.id))

      %{parent: parent, child: child}
    end

    test "grants a consent that was not there before", %{parent: parent, child: child} do
      assert {:ok, _} =
               Family.update_child(child.id, %{first_name: "Emmy"},
                 consents: %{@consent_type => true},
                 parent_id: parent.id
               )

      assert Family.child_has_active_consent?(child.id, @consent_type)
    end

    test "withdraws a consent that is no longer wanted", %{parent: parent, child: child} do
      {:ok, _} = Family.grant_consent(%{parent_id: parent.id, child_id: child.id, consent_type: @consent_type})

      assert {:ok, _} =
               Family.update_child(child.id, %{first_name: "Emmy"},
                 consents: %{@consent_type => false},
                 parent_id: parent.id
               )

      refute Family.child_has_active_consent?(child.id, @consent_type)
    end

    # Re-submitting an unchanged form must not stack a second consent row, and must not
    # fail on the partial unique index either.
    test "leaves an already-granted consent alone", %{parent: parent, child: child} do
      {:ok, _} = Family.grant_consent(%{parent_id: parent.id, child_id: child.id, consent_type: @consent_type})

      assert {:ok, _} =
               Family.update_child(child.id, %{first_name: "Emmy"},
                 consents: %{@consent_type => true},
                 parent_id: parent.id
               )

      assert Family.child_has_active_consent?(child.id, @consent_type)
      assert Repo.aggregate(from(c in Consent, where: c.child_id == ^child.id), :count) == 1
    end

    test "rolls back the update when the consent write fails", %{parent: parent, child: child} do
      assert {:error, {:consent, %Ecto.Changeset{}}} =
               Family.update_child(child.id, %{first_name: "Emmy"},
                 consents: %{"" => true},
                 parent_id: parent.id
               )

      assert Repo.get!(Child, child.id).first_name == "Emma"
    end
  end

  describe "get_child_by_id/1" do
    test "returns an existing child" do
      {:ok, created} = Family.create_child(@valid_attrs)

      assert {:ok, %Child{} = found} = Family.get_child_by_id(created.id)
      assert found.id == created.id
    end

    test "returns :not_found for a missing id" do
      assert {:error, :not_found} = Family.get_child_by_id(Ecto.UUID.generate())
    end

    test "returns :not_found for an invalid UUID" do
      assert {:error, :not_found} = Family.get_child_by_id("invalid-uuid")
    end
  end

  describe "get_children/1" do
    test "lists a guardian's children ordered by name" do
      parent = parent()
      {:ok, _zoe} = Family.create_child(Map.merge(@valid_attrs, %{first_name: "Zoe", parent_id: parent.id}))
      {:ok, _ana} = Family.create_child(Map.merge(@valid_attrs, %{first_name: "Ana", parent_id: parent.id}))

      assert ["Ana", "Zoe"] = Enum.map(Family.get_children(parent.id), & &1.first_name)
    end

    test "returns [] when the guardian has no children" do
      assert Family.get_children(parent().id) == []
    end

    test "scopes to the given guardian only" do
      p1 = parent()
      p2 = parent()
      {:ok, _} = Family.create_child(Map.merge(@valid_attrs, %{first_name: "Mine", parent_id: p1.id}))
      {:ok, _} = Family.create_child(Map.merge(@valid_attrs, %{first_name: "Theirs", parent_id: p2.id}))

      assert ["Mine"] = Enum.map(Family.get_children(p1.id), & &1.first_name)
    end
  end

  describe "child_belongs_to_parent?/2" do
    test "true when the guardian link exists" do
      parent = parent()
      {:ok, child} = Family.create_child(Map.put(@valid_attrs, :parent_id, parent.id))

      assert Family.child_belongs_to_parent?(child.id, parent.id)
    end

    test "false when there is no link" do
      {:ok, child} = Family.create_child(@valid_attrs)
      refute Family.child_belongs_to_parent?(child.id, Ecto.UUID.generate())
    end
  end

  describe "update_child/2" do
    test "updates fields" do
      {:ok, child} = Family.create_child(@valid_attrs)

      assert {:ok, %Child{} = updated} =
               Family.update_child(child.id, %{first_name: "Emily", allergies: "Peanuts"})

      assert updated.first_name == "Emily"
      assert updated.allergies == "Peanuts"
    end

    test "returns :not_found for a missing child" do
      assert {:error, :not_found} = Family.update_child(Ecto.UUID.generate(), %{first_name: "X"})
    end

    test "returns :not_found for an invalid UUID" do
      assert {:error, :not_found} = Family.update_child("invalid-uuid", %{first_name: "X"})
    end

    test "returns a changeset error for invalid data" do
      {:ok, child} = Family.create_child(@valid_attrs)
      assert {:error, %Ecto.Changeset{}} = Family.update_child(child.id, %{first_name: ""})
    end
  end

  describe "delete_child/1" do
    test "deletes an existing child" do
      {:ok, child} = Family.create_child(@valid_attrs)

      assert :ok = Family.delete_child(child.id)
      assert {:error, :not_found} = Family.get_child_by_id(child.id)
    end

    test "returns :not_found for a missing child" do
      assert {:error, :not_found} = Family.delete_child(Ecto.UUID.generate())
    end
  end
end
