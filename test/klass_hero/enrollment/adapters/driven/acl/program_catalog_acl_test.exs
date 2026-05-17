defmodule KlassHero.Enrollment.Adapters.Driven.ACL.ProgramCatalogACLTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Enrollment.Adapters.Driven.ACL.ProgramCatalogACL

  describe "list_program_titles_for_provider/1" do
    test "returns title-to-id map for provider's programs" do
      provider = insert(:provider_profile_schema)

      program1 =
        insert(:program_schema, provider_id: provider.id, title: "Ballsports & Parkour")

      program2 = insert(:program_schema, provider_id: provider.id, title: "Organic Arts")

      result = ProgramCatalogACL.list_program_titles_for_provider(provider.id)

      assert result == %{
               "Ballsports & Parkour" => program1.id,
               "Organic Arts" => program2.id
             }
    end

    test "excludes programs from other providers" do
      provider = insert(:provider_profile_schema)
      other_provider = insert(:provider_profile_schema)

      program = insert(:program_schema, provider_id: provider.id, title: "My Program")
      _other = insert(:program_schema, provider_id: other_provider.id, title: "Other Program")

      result = ProgramCatalogACL.list_program_titles_for_provider(provider.id)

      assert result == %{"My Program" => program.id}
    end

    test "returns empty map when provider has no programs" do
      provider = insert(:provider_profile_schema)

      assert ProgramCatalogACL.list_program_titles_for_provider(provider.id) == %{}
    end

    test "returns empty map for non-existent provider ID" do
      assert ProgramCatalogACL.list_program_titles_for_provider(Ecto.UUID.generate()) == %{}
    end
  end

  describe "program_owned_by?/2" do
    test "returns true when the program belongs to the provider" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)

      assert ProgramCatalogACL.program_owned_by?(program.id, provider.id)
    end

    test "returns false when the program belongs to another provider" do
      other_provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: other_provider.id)
      provider = insert(:provider_profile_schema)

      refute ProgramCatalogACL.program_owned_by?(program.id, provider.id)
    end

    test "returns false for an unknown program id" do
      provider = insert(:provider_profile_schema)

      refute ProgramCatalogACL.program_owned_by?(Ecto.UUID.generate(), provider.id)
    end

    test "returns false for an invalid uuid" do
      provider = insert(:provider_profile_schema)

      refute ProgramCatalogACL.program_owned_by?("not-a-uuid", provider.id)
    end
  end
end
