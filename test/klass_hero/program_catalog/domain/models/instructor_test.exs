defmodule KlassHero.ProgramCatalog.Domain.Models.InstructorTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias KlassHero.ProgramCatalog.Domain.Models.Instructor
  alias KlassHero.Shared.NameUtils

  @valid_attrs %{
    id: "550e8400-e29b-41d4-a716-446655440000",
    name: "Mike Johnson",
    headshot_url: "https://example.com/photo.jpg"
  }

  describe "new/1" do
    test "creates instructor with all fields" do
      assert {:ok, instructor} = Instructor.new(@valid_attrs)
      assert instructor.id == @valid_attrs.id
      assert instructor.name == "Mike Johnson"
      assert instructor.headshot_url == "https://example.com/photo.jpg"
    end

    test "creates instructor without headshot" do
      attrs = Map.delete(@valid_attrs, :headshot_url)
      assert {:ok, instructor} = Instructor.new(attrs)
      assert instructor.headshot_url == nil
    end

    test "rejects missing id" do
      assert {:error, errors} = Instructor.new(%{@valid_attrs | id: ""})
      assert "ID cannot be empty" in errors
    end

    test "rejects missing name" do
      assert {:error, errors} = Instructor.new(%{@valid_attrs | name: ""})
      assert "Name cannot be empty" in errors
    end
  end

  describe "initials/1" do
    test "returns the uppercase initials of the instructor's name" do
      {:ok, instructor} = Instructor.new(%{@valid_attrs | name: "Marie Curie"})
      assert Instructor.initials(instructor) == "MC"
    end

    # initials/1 is a thin delegation to NameUtils.initials_from_name/1, which is
    # itself property-tested. Rather than re-derive the initials algorithm here,
    # assert the wiring: initials/1 must agree with the helper for any name.
    property "delegates to NameUtils.initials_from_name/1 for any name" do
      check all(name <- string(:printable, max_length: 30)) do
        instructor = %Instructor{id: @valid_attrs.id, name: name}
        assert Instructor.initials(instructor) == NameUtils.initials_from_name(name)
      end
    end
  end

  describe "from_persistence/1" do
    test "reconstructs without validation" do
      assert {:ok, instructor} = Instructor.from_persistence(@valid_attrs)
      assert instructor.name == "Mike Johnson"
    end

    test "errors on missing enforce key" do
      assert {:error, :invalid_persistence_data} =
               Instructor.from_persistence(%{id: "abc"})
    end
  end
end
