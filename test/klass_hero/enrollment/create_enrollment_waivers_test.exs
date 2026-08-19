defmodule KlassHero.Enrollment.CreateEnrollmentWaiversTest do
  @moduledoc """
  The waiver gate on `Enrollment.create_enrollment/1`.

  These assert the gate lives *inside* the creating transaction: a blocked enrollment leaves
  no row behind, and an acceptance never exists without its enrollment.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Enrollment
  alias KlassHero.Enrollment.Enrollment, as: EnrollmentSchema
  alias KlassHero.Enrollment.WaiverAcceptance

  defp setup_program(_context \\ %{}) do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)
    {child, parent} = insert_child_with_guardian()
    %{provider: provider, program: program, child: child, parent: parent}
  end

  defp base_params(%{program: program, child: child, parent: parent}) do
    %{program_id: program.id, child_id: child.id, parent_id: parent.id}
  end

  defp add_required_waiver(provider, program, body \\ "I agree to hold the provider harmless.") do
    {:ok, %{waiver: waiver, version: version}} =
      Enrollment.create_waiver(provider.id, %{
        program_id: program.id,
        title: "Liability Waiver",
        required: true,
        body: body
      })

    {waiver, version}
  end

  describe "waiver intent is mandatory" do
    test "omitting :waivers is refused rather than silently defaulting" do
      ctx = setup_program()

      assert {:error, :waiver_intent_required} = Enrollment.create_enrollment(base_params(ctx))
    end

    test "no enrollment row is written when intent is missing" do
      ctx = setup_program()

      Enrollment.create_enrollment(base_params(ctx))

      assert Repo.aggregate(EnrollmentSchema, :count) == 0
    end
  end

  describe ":deferred" do
    test "creates the enrollment without any acceptance" do
      ctx = setup_program()
      {_waiver, _version} = add_required_waiver(ctx.provider, ctx.program)

      params = Map.put(base_params(ctx), :waivers, :deferred)

      assert {:ok, enrollment} = Enrollment.create_enrollment(params)
      assert enrollment.program_id == ctx.program.id
      assert Repo.aggregate(WaiverAcceptance, :count) == 0
    end
  end

  describe "{:accepted, ids}" do
    test "creates the enrollment when the program has no waivers" do
      ctx = setup_program()
      params = Map.put(base_params(ctx), :waivers, {:accepted, []})

      assert {:ok, _enrollment} = Enrollment.create_enrollment(params)
    end

    test "blocks the enrollment when a required waiver is unsigned" do
      ctx = setup_program()
      {_waiver, _version} = add_required_waiver(ctx.provider, ctx.program)

      params = Map.put(base_params(ctx), :waivers, {:accepted, []})

      assert {:error, :waivers_unsigned} = Enrollment.create_enrollment(params)
    end

    test "a blocked enrollment leaves no row behind — the gate is inside the transaction" do
      ctx = setup_program()
      {_waiver, _version} = add_required_waiver(ctx.provider, ctx.program)

      Enrollment.create_enrollment(Map.put(base_params(ctx), :waivers, {:accepted, []}))

      assert Repo.aggregate(EnrollmentSchema, :count) == 0
      assert Repo.aggregate(WaiverAcceptance, :count) == 0
    end

    test "records an acceptance snapshotting the exact text signed" do
      ctx = setup_program()
      {waiver, version} = add_required_waiver(ctx.provider, ctx.program)

      params = Map.put(base_params(ctx), :waivers, {:accepted, [version.id]})

      assert {:ok, enrollment} = Enrollment.create_enrollment(params)

      assert [acceptance] = Repo.all(WaiverAcceptance)
      assert acceptance.enrollment_id == enrollment.id
      assert acceptance.waiver_id == waiver.id
      assert acceptance.waiver_version_id == version.id
      assert acceptance.parent_id == ctx.parent.id
      assert acceptance.body_snapshot == version.body
    end

    test "carries the audit trail onto the acceptance" do
      ctx = setup_program()
      {_waiver, version} = add_required_waiver(ctx.provider, ctx.program)

      params =
        base_params(ctx)
        |> Map.put(:waivers, {:accepted, [version.id]})
        |> Map.put(:audit, %{ip_address: "203.0.113.7", user_agent: "Mozilla/5.0"})

      assert {:ok, _enrollment} = Enrollment.create_enrollment(params)

      assert [acceptance] = Repo.all(WaiverAcceptance)
      assert acceptance.ip_address == "203.0.113.7"
      assert acceptance.user_agent == "Mozilla/5.0"
    end

    test "leaves ip_address nil when no trustworthy client IP was captured" do
      ctx = setup_program()
      {_waiver, version} = add_required_waiver(ctx.provider, ctx.program)

      params =
        base_params(ctx)
        |> Map.put(:waivers, {:accepted, [version.id]})
        |> Map.put(:audit, %{user_agent: "Mozilla/5.0"})

      assert {:ok, _enrollment} = Enrollment.create_enrollment(params)

      assert [acceptance] = Repo.all(WaiverAcceptance)
      assert acceptance.ip_address == nil
    end

    test "signing a superseded version does not satisfy the gate" do
      ctx = setup_program()
      {waiver, v1} = add_required_waiver(ctx.provider, ctx.program, "Original text")
      {:ok, _v2} = Enrollment.publish_waiver_version(ctx.provider.id, waiver.id, "Revised text")

      params = Map.put(base_params(ctx), :waivers, {:accepted, [v1.id]})

      assert {:error, :waivers_unsigned} = Enrollment.create_enrollment(params)
    end

    test "an optional waiver is recorded when signed but never blocks" do
      ctx = setup_program()

      {:ok, %{version: optional_version}} =
        Enrollment.create_waiver(ctx.provider.id, %{
          program_id: ctx.program.id,
          title: "Photo release",
          required: false,
          body: "You may photograph my child."
        })

      # Not signing it still enrolls.
      assert {:ok, _} = Enrollment.create_enrollment(Map.put(base_params(ctx), :waivers, {:accepted, []}))
      assert Repo.aggregate(WaiverAcceptance, :count) == 0

      # Signing it records the acceptance.
      {other_child, other_parent} = insert_child_with_guardian()

      params = %{
        program_id: ctx.program.id,
        child_id: other_child.id,
        parent_id: other_parent.id,
        waivers: {:accepted, [optional_version.id]}
      }

      assert {:ok, _} = Enrollment.create_enrollment(params)
      assert [acceptance] = Repo.all(WaiverAcceptance)
      assert acceptance.waiver_version_id == optional_version.id
    end

    test "an archived required waiver no longer blocks" do
      ctx = setup_program()
      {waiver, _version} = add_required_waiver(ctx.provider, ctx.program)
      {:ok, _} = Enrollment.archive_waiver(ctx.provider.id, waiver.id)

      assert {:ok, _} = Enrollment.create_enrollment(Map.put(base_params(ctx), :waivers, {:accepted, []}))
    end
  end
end
