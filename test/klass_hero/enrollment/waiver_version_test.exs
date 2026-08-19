defmodule KlassHero.Enrollment.WaiverVersionTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.Enrollment.WaiverVersion

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        waiver_id: Ecto.UUID.generate(),
        body: "I agree to hold the provider harmless.",
        version: 1,
        published_at: DateTime.utc_now()
      },
      overrides
    )
  end

  describe "changeset/2" do
    test "is valid with waiver_id, body, version and published_at" do
      assert WaiverVersion.changeset(%WaiverVersion{}, valid_attrs()).valid?
    end

    test "requires body" do
      changeset = WaiverVersion.changeset(%WaiverVersion{}, valid_attrs(%{body: nil}))
      refute changeset.valid?
      assert %{body: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects a blank body" do
      changeset = WaiverVersion.changeset(%WaiverVersion{}, valid_attrs(%{body: "   "}))
      refute changeset.valid?
      assert %{body: [_]} = errors_on(changeset)
    end

    test "requires waiver_id" do
      changeset = WaiverVersion.changeset(%WaiverVersion{}, Map.delete(valid_attrs(), :waiver_id))
      refute changeset.valid?
      assert %{waiver_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects a body longer than the maximum" do
      long = String.duplicate("a", WaiverVersion.body_max_length() + 1)
      changeset = WaiverVersion.changeset(%WaiverVersion{}, valid_attrs(%{body: long}))
      refute changeset.valid?
      assert %{body: [_]} = errors_on(changeset)
    end

    test "rejects version below 1" do
      changeset = WaiverVersion.changeset(%WaiverVersion{}, valid_attrs(%{version: 0}))
      refute changeset.valid?
      assert %{version: [_]} = errors_on(changeset)
    end
  end

  describe "publish/2" do
    test "the first version of a waiver is version 1" do
      waiver_id = Ecto.UUID.generate()
      assert {:ok, attrs} = WaiverVersion.publish(waiver_id, "First text", nil)
      assert attrs.waiver_id == waiver_id
      assert attrs.version == 1
      assert attrs.body == "First text"
      assert %DateTime{} = attrs.published_at
    end

    test "publishing over an existing version increments it" do
      previous = %WaiverVersion{version: 3}
      assert {:ok, attrs} = WaiverVersion.publish(Ecto.UUID.generate(), "Revised text", previous)
      assert attrs.version == 4
    end

    test "rejects a blank body without allocating a version" do
      assert {:error, [body: _]} = WaiverVersion.publish(Ecto.UUID.generate(), "   ", nil)
    end

    test "trims surrounding whitespace from the published body" do
      assert {:ok, attrs} = WaiverVersion.publish(Ecto.UUID.generate(), "  Text  ", nil)
      assert attrs.body == "Text"
    end
  end
end
