defmodule KlassHero.Enrollment.WaiverTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.Enrollment.Waiver

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{program_id: Ecto.UUID.generate(), title: "Liability Waiver", required: true},
      overrides
    )
  end

  describe "changeset/2" do
    test "is valid with program_id, title and required" do
      assert Waiver.changeset(%Waiver{}, valid_attrs()).valid?
    end

    test "requires program_id" do
      changeset = Waiver.changeset(%Waiver{}, Map.delete(valid_attrs(), :program_id))
      refute changeset.valid?
      assert %{program_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires title" do
      changeset = Waiver.changeset(%Waiver{}, valid_attrs(%{title: nil}))
      refute changeset.valid?
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects a title longer than 200 characters" do
      changeset = Waiver.changeset(%Waiver{}, valid_attrs(%{title: String.duplicate("a", 201)}))
      refute changeset.valid?
      assert %{title: [_]} = errors_on(changeset)
    end

    test "defaults required to true when omitted" do
      changeset = Waiver.changeset(%Waiver{}, Map.delete(valid_attrs(), :required))
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :required) == true
    end

    test "accepts an optional waiver" do
      changeset = Waiver.changeset(%Waiver{}, valid_attrs(%{required: false}))
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :required) == false
    end

    test "does not cast archived_at — archiving goes through archive_changeset/2" do
      changeset = Waiver.changeset(%Waiver{}, valid_attrs(%{archived_at: DateTime.utc_now()}))
      assert Ecto.Changeset.get_field(changeset, :archived_at) == nil
    end
  end

  describe "archive_changeset/2" do
    test "stamps archived_at" do
      at = DateTime.utc_now()
      changeset = Waiver.archive_changeset(%Waiver{}, at)
      assert Ecto.Changeset.get_field(changeset, :archived_at) == at
    end
  end

  describe "active?/1 and archived?/1" do
    test "a waiver with no archived_at is active" do
      assert Waiver.active?(%Waiver{archived_at: nil})
      refute Waiver.archived?(%Waiver{archived_at: nil})
    end

    test "a waiver with archived_at is archived" do
      waiver = %Waiver{archived_at: DateTime.utc_now()}
      refute Waiver.active?(waiver)
      assert Waiver.archived?(waiver)
    end
  end
end
