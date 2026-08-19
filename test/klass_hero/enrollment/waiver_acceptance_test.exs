defmodule KlassHero.Enrollment.WaiverAcceptanceTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.Enrollment.WaiverAcceptance
  alias KlassHero.Enrollment.WaiverVersion

  defp a_version(overrides \\ %{}) do
    struct!(
      %WaiverVersion{
        id: Ecto.UUID.generate(),
        waiver_id: Ecto.UUID.generate(),
        body: "I agree to hold the provider harmless.",
        version: 2,
        published_at: DateTime.utc_now()
      },
      overrides
    )
  end

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        waiver_version_id: Ecto.UUID.generate(),
        waiver_id: Ecto.UUID.generate(),
        enrollment_id: Ecto.UUID.generate(),
        parent_id: Ecto.UUID.generate(),
        accepted_at: DateTime.utc_now(),
        body_snapshot: "I agree to hold the provider harmless."
      },
      overrides
    )
  end

  describe "changeset/2" do
    test "is valid with every required field" do
      assert WaiverAcceptance.changeset(%WaiverAcceptance{}, valid_attrs()).valid?
    end

    test "requires the version it was signed against" do
      changeset =
        WaiverAcceptance.changeset(%WaiverAcceptance{}, Map.delete(valid_attrs(), :waiver_version_id))

      refute changeset.valid?
      assert %{waiver_version_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires a body snapshot — an acceptance without the text proves nothing" do
      changeset = WaiverAcceptance.changeset(%WaiverAcceptance{}, valid_attrs(%{body_snapshot: nil}))
      refute changeset.valid?
      assert %{body_snapshot: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires enrollment_id and parent_id" do
      changeset =
        WaiverAcceptance.changeset(
          %WaiverAcceptance{},
          valid_attrs(%{enrollment_id: nil, parent_id: nil})
        )

      refute changeset.valid?
      errors = errors_on(changeset)
      assert %{enrollment_id: [_]} = errors
      assert %{parent_id: [_]} = errors
    end

    test "ip_address and user_agent are optional" do
      assert WaiverAcceptance.changeset(%WaiverAcceptance{}, valid_attrs()).valid?
    end
  end

  describe "accept/3" do
    test "snapshots the version's body verbatim" do
      version = a_version()
      enrollment_id = Ecto.UUID.generate()
      parent_id = Ecto.UUID.generate()

      attrs = WaiverAcceptance.accept(version, %{enrollment_id: enrollment_id, parent_id: parent_id}, %{})

      assert attrs.body_snapshot == version.body
      assert attrs.waiver_version_id == version.id
      assert attrs.waiver_id == version.waiver_id
      assert attrs.enrollment_id == enrollment_id
      assert attrs.parent_id == parent_id
      assert %DateTime{} = attrs.accepted_at
    end

    test "carries the audit trail through" do
      attrs =
        WaiverAcceptance.accept(
          a_version(),
          %{enrollment_id: Ecto.UUID.generate(), parent_id: Ecto.UUID.generate()},
          %{ip_address: "203.0.113.7", user_agent: "Mozilla/5.0"}
        )

      assert attrs.ip_address == "203.0.113.7"
      assert attrs.user_agent == "Mozilla/5.0"
    end

    test "stores nil rather than a placeholder when the client IP is unknown" do
      attrs =
        WaiverAcceptance.accept(
          a_version(),
          %{enrollment_id: Ecto.UUID.generate(), parent_id: Ecto.UUID.generate()},
          %{user_agent: "Mozilla/5.0"}
        )

      assert attrs.ip_address == nil
      assert attrs.user_agent == "Mozilla/5.0"
    end
  end
end
