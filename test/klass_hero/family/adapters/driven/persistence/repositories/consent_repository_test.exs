defmodule KlassHero.Family.Adapters.Driven.Persistence.Repositories.ConsentRepositoryTest do
  @moduledoc """
  Tests for the ConsentRepository adapter.
  """

  use KlassHero.DataCase, async: true

  alias KlassHero.Family
  alias KlassHero.Family.Adapters.Driven.Persistence.Repositories.ConsentRepository
  alias KlassHero.Family.Domain.Models.Consent

  defp create_parent do
    user = KlassHero.AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:parent])
    {:ok, parent} = Family.create_parent_profile(%{identity_id: user.id})
    parent
  end

  defp create_child(parent) do
    {:ok, child} =
      Family.create_child(%{
        parent_id: parent.id,
        first_name: "Emma",
        last_name: "Smith",
        date_of_birth: ~D[2015-06-15]
      })

    child
  end

  describe "grant/1" do
    test "grants consent and returns domain entity" do
      parent = create_parent()
      child = create_child(parent)

      attrs = %{
        parent_id: parent.id,
        child_id: child.id,
        consent_type: "provider_data_sharing",
        granted_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      assert {:ok, %Consent{} = consent} = ConsentRepository.grant(attrs)
      assert is_binary(consent.id)
      assert consent.parent_id == parent.id
      assert consent.child_id == child.id
      assert consent.consent_type == "provider_data_sharing"
      assert %DateTime{} = consent.granted_at
      assert is_nil(consent.withdrawn_at)
    end

    test "returns changeset error for missing required fields" do
      assert {:error, %Ecto.Changeset{}} = ConsentRepository.grant(%{})
    end
  end

  describe "withdraw/2" do
    test "withdraws consent by persisting the given withdrawn_at timestamp" do
      parent = create_parent()
      child = create_child(parent)

      {:ok, granted} =
        ConsentRepository.grant(%{
          parent_id: parent.id,
          child_id: child.id,
          consent_type: "provider_data_sharing",
          granted_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      withdrawn_at = DateTime.utc_now() |> DateTime.truncate(:second)

      assert {:ok, %Consent{} = withdrawn} =
               ConsentRepository.withdraw(granted.id, withdrawn_at)

      assert withdrawn.withdrawn_at == withdrawn_at
      assert withdrawn.id == granted.id
    end

    test "returns :not_found for non-existent consent" do
      withdrawn_at = DateTime.utc_now() |> DateTime.truncate(:second)
      assert {:error, :not_found} = ConsentRepository.withdraw(Ecto.UUID.generate(), withdrawn_at)
    end

    test "returns :not_found for invalid UUID" do
      withdrawn_at = DateTime.utc_now() |> DateTime.truncate(:second)
      assert {:error, :not_found} = ConsentRepository.withdraw("invalid-uuid", withdrawn_at)
    end
  end

  describe "get_active_for_child/2" do
    test "returns active consent for child and type" do
      parent = create_parent()
      child = create_child(parent)

      {:ok, granted} =
        ConsentRepository.grant(%{
          parent_id: parent.id,
          child_id: child.id,
          consent_type: "provider_data_sharing",
          granted_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      assert {:ok, %Consent{} = found} =
               ConsentRepository.get_active_for_child(child.id, "provider_data_sharing")

      assert found.id == granted.id
    end

    test "does not return withdrawn consents" do
      parent = create_parent()
      child = create_child(parent)

      {:ok, granted} =
        ConsentRepository.grant(%{
          parent_id: parent.id,
          child_id: child.id,
          consent_type: "provider_data_sharing",
          granted_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      ConsentRepository.withdraw(granted.id, DateTime.utc_now() |> DateTime.truncate(:second))

      assert {:error, :not_found} =
               ConsentRepository.get_active_for_child(child.id, "provider_data_sharing")
    end

    test "returns :not_found when no consent exists" do
      child_id = Ecto.UUID.generate()

      assert {:error, :not_found} =
               ConsentRepository.get_active_for_child(child_id, "provider_data_sharing")
    end
  end

  describe "list_active_by_child/1" do
    test "lists active consents for a child" do
      parent = create_parent()
      child = create_child(parent)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _} =
        ConsentRepository.grant(%{
          parent_id: parent.id,
          child_id: child.id,
          consent_type: "provider_data_sharing",
          granted_at: now
        })

      {:ok, _} =
        ConsentRepository.grant(%{
          parent_id: parent.id,
          child_id: child.id,
          consent_type: "photo_marketing",
          granted_at: now
        })

      consents = ConsentRepository.list_active_by_child(child.id)

      assert length(consents) == 2
      types = Enum.map(consents, & &1.consent_type)
      assert "photo_marketing" in types
      assert "provider_data_sharing" in types
    end

    test "excludes withdrawn consents from listing" do
      parent = create_parent()
      child = create_child(parent)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, to_withdraw} =
        ConsentRepository.grant(%{
          parent_id: parent.id,
          child_id: child.id,
          consent_type: "provider_data_sharing",
          granted_at: now
        })

      {:ok, _} =
        ConsentRepository.grant(%{
          parent_id: parent.id,
          child_id: child.id,
          consent_type: "photo_marketing",
          granted_at: now
        })

      ConsentRepository.withdraw(to_withdraw.id, DateTime.utc_now() |> DateTime.truncate(:second))

      consents = ConsentRepository.list_active_by_child(child.id)

      assert length(consents) == 1
      assert Enum.at(consents, 0).consent_type == "photo_marketing"
    end

    test "returns empty list when child has no consents" do
      assert ConsentRepository.list_active_by_child(Ecto.UUID.generate()) == []
    end
  end

  describe "list_all_by_child/1" do
    test "returns both active and withdrawn consents" do
      parent = create_parent()
      child = create_child(parent)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, active} =
        ConsentRepository.grant(%{
          parent_id: parent.id,
          child_id: child.id,
          consent_type: "provider_data_sharing",
          granted_at: now
        })

      {:ok, to_withdraw} =
        ConsentRepository.grant(%{
          parent_id: parent.id,
          child_id: child.id,
          consent_type: "photo_marketing",
          granted_at: now
        })

      ConsentRepository.withdraw(to_withdraw.id, DateTime.utc_now() |> DateTime.truncate(:second))

      consents = ConsentRepository.list_all_by_child(child.id)

      assert length(consents) == 2

      ids = Enum.map(consents, & &1.id)
      assert active.id in ids
      assert to_withdraw.id in ids
    end

    test "orders by consent_type asc, granted_at desc" do
      parent = create_parent()
      child = create_child(parent)
      earlier = ~U[2025-01-01 12:00:00Z]
      later = ~U[2025-06-01 12:00:00Z]
      withdrawn_at = ~U[2025-03-01 12:00:00Z]

      {:ok, _} =
        ConsentRepository.grant(%{
          parent_id: parent.id,
          child_id: child.id,
          consent_type: "provider_data_sharing",
          granted_at: earlier
        })

      # Grant first photo_marketing consent, then withdraw it to allow a second
      {:ok, first_photo} =
        ConsentRepository.grant(%{
          parent_id: parent.id,
          child_id: child.id,
          consent_type: "photo_marketing",
          granted_at: earlier
        })

      {:ok, _} = ConsentRepository.withdraw(first_photo.id, withdrawn_at)

      {:ok, _} =
        ConsentRepository.grant(%{
          parent_id: parent.id,
          child_id: child.id,
          consent_type: "photo_marketing",
          granted_at: later
        })

      consents = ConsentRepository.list_all_by_child(child.id)

      types = Enum.map(consents, & &1.consent_type)
      # Trigger: "photo_marketing" sorts before "provider_data_sharing" alphabetically
      assert types == ["photo_marketing", "photo_marketing", "provider_data_sharing"]

      # Within "photo_marketing" type, later granted_at comes first (desc)
      [photo1, photo2 | _] = consents
      assert DateTime.after?(photo1.granted_at, photo2.granted_at)
    end

    test "returns empty list when child has no consents" do
      assert ConsentRepository.list_all_by_child(Ecto.UUID.generate()) == []
    end
  end

  describe "delete_all_for_child/1" do
    test "deletes all consents for child and returns count" do
      parent = create_parent()
      child = create_child(parent)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _} =
        ConsentRepository.grant(%{
          parent_id: parent.id,
          child_id: child.id,
          consent_type: "provider_data_sharing",
          granted_at: now
        })

      {:ok, _} =
        ConsentRepository.grant(%{
          parent_id: parent.id,
          child_id: child.id,
          consent_type: "photo_marketing",
          granted_at: now
        })

      assert {:ok, 2} = ConsentRepository.delete_all_for_child(child.id)

      # Verify consents are actually gone
      assert ConsentRepository.list_active_by_child(child.id) == []
    end

    test "returns {:ok, 0} for child with no consents" do
      assert {:ok, 0} = ConsentRepository.delete_all_for_child(Ecto.UUID.generate())
    end

    test "only deletes specified child's consents" do
      parent = create_parent()
      child_a = create_child(parent)
      child_b = create_child(parent)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _} =
        ConsentRepository.grant(%{
          parent_id: parent.id,
          child_id: child_a.id,
          consent_type: "provider_data_sharing",
          granted_at: now
        })

      {:ok, _} =
        ConsentRepository.grant(%{
          parent_id: parent.id,
          child_id: child_b.id,
          consent_type: "provider_data_sharing",
          granted_at: now
        })

      assert {:ok, 1} = ConsentRepository.delete_all_for_child(child_a.id)

      # Child B's consent should remain
      assert {:ok, %Consent{}} =
               ConsentRepository.get_active_for_child(child_b.id, "provider_data_sharing")
    end
  end
end
