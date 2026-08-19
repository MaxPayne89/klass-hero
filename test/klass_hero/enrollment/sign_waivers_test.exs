defmodule KlassHero.Enrollment.SignWaiversTest do
  @moduledoc """
  Signing waivers *after* enrollment — the deferred path, where an invite-claimed enrollment
  was created by a background job with no parent present.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Enrollment
  alias KlassHero.Enrollment.WaiverAcceptance

  defp deferred_enrollment(_context \\ %{}) do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)
    {child, parent} = insert_child_with_guardian()

    {:ok, %{waiver: waiver, version: version}} =
      Enrollment.create_waiver(provider.id, %{
        program_id: program.id,
        title: "Liability Waiver",
        required: true,
        body: "I agree to hold the provider harmless."
      })

    {:ok, enrollment} =
      Enrollment.create_enrollment(%{
        program_id: program.id,
        child_id: child.id,
        parent_id: parent.id,
        waivers: :deferred
      })

    %{
      provider: provider,
      program: program,
      parent: parent,
      enrollment: enrollment,
      waiver: waiver,
      version: version
    }
  end

  describe "list_enrollment_waivers/1" do
    test "reports a required waiver as outstanding after a deferred enrollment" do
      ctx = deferred_enrollment()

      assert [entry] = Enrollment.list_enrollment_waivers(ctx.enrollment.id)
      assert entry.waiver.id == ctx.waiver.id
      assert entry.version.id == ctx.version.id
      refute entry.signed?
    end

    test "reports it as signed once the parent signs" do
      ctx = deferred_enrollment()

      {:ok, _} = Enrollment.sign_waivers(ctx.enrollment.id, ctx.parent.id, [ctx.version.id], %{})

      assert [entry] = Enrollment.list_enrollment_waivers(ctx.enrollment.id)
      assert entry.signed?
    end
  end

  describe "sign_waivers/4" do
    test "records an acceptance with the version's text" do
      ctx = deferred_enrollment()

      assert {:ok, [acceptance]} =
               Enrollment.sign_waivers(ctx.enrollment.id, ctx.parent.id, [ctx.version.id], %{
                 ip_address: "203.0.113.7",
                 user_agent: "Mozilla/5.0"
               })

      assert acceptance.enrollment_id == ctx.enrollment.id
      assert acceptance.parent_id == ctx.parent.id
      assert acceptance.body_snapshot == ctx.version.body
      assert acceptance.ip_address == "203.0.113.7"
    end

    test "refuses a parent who is not the enrolling parent" do
      ctx = deferred_enrollment()
      {_other_child, other_parent} = insert_child_with_guardian()

      assert {:error, :not_found} =
               Enrollment.sign_waivers(ctx.enrollment.id, other_parent.id, [ctx.version.id], %{})

      assert Repo.aggregate(WaiverAcceptance, :count) == 0
    end

    test "refuses an unknown enrollment" do
      ctx = deferred_enrollment()

      assert {:error, :not_found} =
               Enrollment.sign_waivers(Ecto.UUID.generate(), ctx.parent.id, [ctx.version.id], %{})
    end

    test "signing twice does not duplicate the acceptance" do
      ctx = deferred_enrollment()

      {:ok, _} = Enrollment.sign_waivers(ctx.enrollment.id, ctx.parent.id, [ctx.version.id], %{})

      assert {:error, _} = Enrollment.sign_waivers(ctx.enrollment.id, ctx.parent.id, [ctx.version.id], %{})
      assert Repo.aggregate(WaiverAcceptance, :count) == 1
    end

    test "ignores a version that does not belong to the enrollment's program" do
      ctx = deferred_enrollment()
      stranger = insert(:provider_profile_schema)
      stranger_program = insert(:program_schema, provider_id: stranger.id)

      {:ok, %{version: foreign_version}} =
        Enrollment.create_waiver(stranger.id, %{
          program_id: stranger_program.id,
          title: "Elsewhere",
          body: "Not this program"
        })

      assert {:ok, []} = Enrollment.sign_waivers(ctx.enrollment.id, ctx.parent.id, [foreign_version.id], %{})
      assert Repo.aggregate(WaiverAcceptance, :count) == 0
    end
  end

  describe "waiver_status_for_enrollments/1" do
    test "an enrollment with an unsigned required waiver is :unsigned" do
      ctx = deferred_enrollment()
      id = ctx.enrollment.id

      assert Enrollment.waiver_status_for_enrollments([id]) == %{id => :unsigned}
    end

    test "becomes :signed once every required waiver is signed" do
      ctx = deferred_enrollment()
      {:ok, _} = Enrollment.sign_waivers(ctx.enrollment.id, ctx.parent.id, [ctx.version.id], %{})

      id = ctx.enrollment.id
      assert Enrollment.waiver_status_for_enrollments([id]) == %{id => :signed}
    end

    test "is :not_required for a program with no required waivers" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      {child, parent} = insert_child_with_guardian()

      {:ok, enrollment} =
        Enrollment.create_enrollment(%{
          program_id: program.id,
          child_id: child.id,
          parent_id: parent.id,
          waivers: {:accepted, []}
        })

      id = enrollment.id
      assert Enrollment.waiver_status_for_enrollments([id]) == %{id => :not_required}
    end
  end
end
