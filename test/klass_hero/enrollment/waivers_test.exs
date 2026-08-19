defmodule KlassHero.Enrollment.WaiversTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Enrollment
  alias KlassHero.Enrollment.Waiver

  defp provider_with_program(_context \\ %{}) do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)
    %{provider: provider, program: program}
  end

  describe "create_waiver/2" do
    test "creates the waiver and its first version together" do
      %{provider: provider, program: program} = provider_with_program()

      assert {:ok, %{waiver: waiver, version: version}} =
               Enrollment.create_waiver(provider.id, %{
                 program_id: program.id,
                 title: "Liability Waiver",
                 required: true,
                 body: "I agree to hold the provider harmless."
               })

      assert waiver.program_id == program.id
      assert waiver.title == "Liability Waiver"
      assert waiver.required
      assert version.waiver_id == waiver.id
      assert version.version == 1
      assert version.body == "I agree to hold the provider harmless."
    end

    test "refuses a program the provider does not own" do
      %{provider: provider} = provider_with_program()
      %{program: someone_elses} = provider_with_program()

      assert {:error, :not_found} =
               Enrollment.create_waiver(provider.id, %{
                 program_id: someone_elses.id,
                 title: "Liability Waiver",
                 body: "Text"
               })
    end

    test "rejects a blank body without creating the waiver" do
      %{provider: provider, program: program} = provider_with_program()

      assert {:error, _} =
               Enrollment.create_waiver(provider.id, %{
                 program_id: program.id,
                 title: "Liability Waiver",
                 body: "   "
               })

      assert Enrollment.list_program_waivers(program.id) == []
    end
  end

  describe "publish_waiver_version/3" do
    test "appends a new version and leaves the old one intact" do
      %{provider: provider, program: program} = provider_with_program()

      {:ok, %{waiver: waiver, version: v1}} =
        Enrollment.create_waiver(provider.id, %{
          program_id: program.id,
          title: "Liability Waiver",
          body: "Original text"
        })

      assert {:ok, v2} = Enrollment.publish_waiver_version(provider.id, waiver.id, "Revised text")
      assert v2.version == 2
      assert v2.body == "Revised text"

      # The v1 row is untouched — this is the whole point of append-only versioning.
      assert reloaded_v1 = Repo.get(Enrollment.WaiverVersion, v1.id)
      assert reloaded_v1.body == "Original text"
      assert reloaded_v1.version == 1
    end

    test "refuses a waiver belonging to another provider's program" do
      %{provider: provider, program: program} = provider_with_program()
      %{provider: other} = provider_with_program()

      {:ok, %{waiver: waiver}} =
        Enrollment.create_waiver(provider.id, %{
          program_id: program.id,
          title: "Liability Waiver",
          body: "Original text"
        })

      assert {:error, :not_found} = Enrollment.publish_waiver_version(other.id, waiver.id, "Hijacked")
    end
  end

  describe "archive_waiver/2" do
    test "retires the waiver without deleting it" do
      %{provider: provider, program: program} = provider_with_program()

      {:ok, %{waiver: waiver}} =
        Enrollment.create_waiver(provider.id, %{
          program_id: program.id,
          title: "Liability Waiver",
          body: "Text"
        })

      assert {:ok, archived} = Enrollment.archive_waiver(provider.id, waiver.id)
      assert Waiver.archived?(archived)

      # Still on disk, just not offered any more.
      assert Repo.get(Waiver, waiver.id)
      assert Enrollment.list_program_waivers(program.id) == []
    end
  end

  describe "list_program_waivers/1" do
    test "returns active waivers with their latest version" do
      %{provider: provider, program: program} = provider_with_program()

      {:ok, %{waiver: waiver}} =
        Enrollment.create_waiver(provider.id, %{
          program_id: program.id,
          title: "Liability Waiver",
          body: "Original text"
        })

      {:ok, _v2} = Enrollment.publish_waiver_version(provider.id, waiver.id, "Revised text")

      assert [entry] = Enrollment.list_program_waivers(program.id)
      assert entry.waiver.id == waiver.id
      assert entry.version.version == 2
      assert entry.version.body == "Revised text"
    end

    test "is empty for a program with no waivers" do
      %{program: program} = provider_with_program()
      assert Enrollment.list_program_waivers(program.id) == []
    end
  end

  describe "list_required_waiver_versions/1" do
    test "returns only the latest version of each required, active waiver" do
      %{provider: provider, program: program} = provider_with_program()

      {:ok, %{waiver: required}} =
        Enrollment.create_waiver(provider.id, %{
          program_id: program.id,
          title: "Liability",
          required: true,
          body: "v1"
        })

      {:ok, _} = Enrollment.publish_waiver_version(provider.id, required.id, "v2")

      {:ok, %{waiver: _optional}} =
        Enrollment.create_waiver(provider.id, %{
          program_id: program.id,
          title: "Photo release",
          required: false,
          body: "optional text"
        })

      {:ok, %{waiver: retired}} =
        Enrollment.create_waiver(provider.id, %{
          program_id: program.id,
          title: "Old form",
          required: true,
          body: "retired text"
        })

      {:ok, _} = Enrollment.archive_waiver(provider.id, retired.id)

      versions = Enrollment.list_required_waiver_versions(program.id)

      assert [version] = versions
      assert version.waiver_id == required.id
      assert version.version == 2
    end
  end
end
