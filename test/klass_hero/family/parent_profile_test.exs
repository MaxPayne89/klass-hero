defmodule KlassHero.Family.ParentProfileTest do
  @moduledoc """
  Unit tests for the ParentProfile schema: changeset validation and the pure
  helper functions.
  """

  use ExUnit.Case, async: true

  alias KlassHero.Family.ParentProfile

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(%{identity_id: Ecto.UUID.generate()}, overrides)
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end

  describe "changeset/2 - valid input" do
    test "valid with only identity_id" do
      assert ParentProfile.changeset(%ParentProfile{}, valid_attrs()).valid?
    end

    test "valid with all fields" do
      attrs =
        valid_attrs(%{
          display_name: "John Doe",
          phone: "+1234567890",
          location: "Berlin",
          notification_preferences: %{email: true}
        })

      assert ParentProfile.changeset(%ParentProfile{}, attrs).valid?
    end
  end

  describe "changeset/2 - validation errors" do
    test "is invalid without identity_id" do
      changeset = ParentProfile.changeset(%ParentProfile{}, %{})

      refute changeset.valid?
      assert %{identity_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "is invalid when display_name exceeds 100 characters" do
      changeset =
        ParentProfile.changeset(%ParentProfile{}, valid_attrs(%{display_name: String.duplicate("a", 101)}))

      refute changeset.valid?
      assert %{display_name: [_]} = errors_on(changeset)
    end
  end

  describe "has_notification_preferences?/1" do
    test "true when preferences are present" do
      assert ParentProfile.has_notification_preferences?(%ParentProfile{notification_preferences: %{email: true}})
    end

    test "false when nil or empty" do
      refute ParentProfile.has_notification_preferences?(%ParentProfile{notification_preferences: nil})
      refute ParentProfile.has_notification_preferences?(%ParentProfile{notification_preferences: %{}})
    end
  end
end
