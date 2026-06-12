defmodule KlassHero.Provider.Adapters.Driven.Persistence.Schemas.ProviderProfileSchemaTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.ProviderProfileSchema

  describe "admin_changeset/3" do
    setup do
      user = KlassHero.AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])

      {:ok, schema} =
        %ProviderProfileSchema{}
        |> ProviderProfileSchema.changeset(%{
          identity_id: user.id,
          business_name: "Test Business"
        })
        |> KlassHero.Repo.insert()

      %{schema: schema}
    end

    test "casts verified", %{schema: schema} do
      admin_id = Ecto.UUID.generate()
      metadata = [assigns: %{current_scope: %{user: %{id: admin_id}}}]

      changeset =
        ProviderProfileSchema.admin_changeset(
          schema,
          %{verified: true},
          metadata
        )

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :verified) == true
    end

    test "sets verified_at and verified_by_id when verified changes to true", %{schema: schema} do
      admin_id = Ecto.UUID.generate()
      metadata = [assigns: %{current_scope: %{user: %{id: admin_id}}}]

      changeset =
        ProviderProfileSchema.admin_changeset(
          schema,
          %{verified: true},
          metadata
        )

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :verified_at) != nil
      assert Ecto.Changeset.get_change(changeset, :verified_by_id) == admin_id
    end

    test "clears verified_at and verified_by_id when verified changes to false", %{schema: schema} do
      metadata = [assigns: %{current_scope: %{user: %{id: "some-admin-id"}}}]

      changeset =
        ProviderProfileSchema.admin_changeset(
          %{
            schema
            | verified: true,
              verified_at: DateTime.utc_now(),
              verified_by_id: "some-admin-id"
          },
          %{verified: false},
          metadata
        )

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :verified_at) == nil
      assert Ecto.Changeset.get_change(changeset, :verified_by_id) == nil
    end

    test "does not change verified_at when verified is unchanged", %{schema: schema} do
      metadata = [assigns: %{current_scope: %{user: %{id: "some-admin-id"}}}]

      changeset = ProviderProfileSchema.admin_changeset(schema, %{}, metadata)

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :verified_at) == nil
      assert Ecto.Changeset.get_change(changeset, :verified_by_id) == nil
    end

    test "ignores provider-owned fields", %{schema: schema} do
      changeset =
        ProviderProfileSchema.admin_changeset(
          schema,
          %{
            business_name: "Hacked Name",
            description: "Hacked Desc",
            phone: "555-HACK",
            website: "https://hacked.com",
            address: "Hacked Address",
            subscription_tier: "professional"
          },
          %{}
        )

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :business_name) == nil
      assert Ecto.Changeset.get_change(changeset, :description) == nil
      assert Ecto.Changeset.get_change(changeset, :phone) == nil
      assert Ecto.Changeset.get_change(changeset, :website) == nil
      assert Ecto.Changeset.get_change(changeset, :address) == nil
      assert Ecto.Changeset.get_change(changeset, :subscription_tier) == nil
    end
  end
end
