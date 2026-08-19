defmodule KlassHeroWeb.EnrollmentWaiversLiveTest do
  @moduledoc """
  The standalone signing page for enrollments created without a signer present.
  """
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.Factory
  import Phoenix.LiveViewTest

  alias KlassHero.Enrollment
  alias KlassHero.Enrollment.WaiverAcceptance
  alias KlassHero.Repo

  setup :register_and_log_in_user

  setup %{user: user} do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)
    parent = insert(:parent_profile_schema, identity_id: user.id)
    {child, _} = insert_child_with_guardian(parent: parent)

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

  describe "mount" do
    test "shows the outstanding waiver text and a checkbox", %{
      conn: conn,
      enrollment: enrollment,
      waiver: waiver
    } do
      {:ok, view, _html} = live(conn, ~p"/enrollments/#{enrollment.id}/waivers")

      assert has_element?(view, "#waiver-#{waiver.id}")
      assert has_element?(view, "#sign-waiver-#{waiver.id}")
      assert render(view) =~ "I agree to hold the provider harmless."
    end

    test "labels both required and optional waivers", %{
      conn: conn,
      enrollment: enrollment,
      provider: provider,
      program: program,
      waiver: blocking
    } do
      {:ok, %{waiver: skippable}} =
        Enrollment.create_waiver(provider.id, %{
          program_id: program.id,
          title: "Photo release",
          required: false,
          body: "Optional text."
        })

      {:ok, view, _html} = live(conn, ~p"/enrollments/#{enrollment.id}/waivers")

      assert has_element?(view, "#waiver-#{blocking.id}", "Required")
      assert has_element?(view, "#waiver-#{skippable.id}", "(optional)")
    end

    test "redirects when the enrollment belongs to another parent", %{conn: conn} do
      other_provider = insert(:provider_profile_schema)
      other_program = insert(:program_schema, provider_id: other_provider.id)
      {other_child, other_parent} = insert_child_with_guardian()

      {:ok, foreign} =
        Enrollment.create_enrollment(%{
          program_id: other_program.id,
          child_id: other_child.id,
          parent_id: other_parent.id,
          waivers: :deferred
        })

      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               live(conn, ~p"/enrollments/#{foreign.id}/waivers")
    end

    test "redirects for an unknown enrollment", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               live(conn, ~p"/enrollments/#{Ecto.UUID.generate()}/waivers")
    end
  end

  describe "signing" do
    test "records the acceptance and returns to the dashboard", %{
      conn: conn,
      enrollment: enrollment,
      parent: parent,
      version: version
    } do
      conn = Plug.Conn.put_req_header(conn, "user-agent", "TestBrowser/1.0")
      {:ok, view, _html} = live(conn, ~p"/enrollments/#{enrollment.id}/waivers")

      view
      |> form("#sign-waivers-form", %{"waiver_version_ids" => [version.id]})
      |> render_submit()

      assert_redirect(view, ~p"/dashboard")

      assert [acceptance] = Repo.all(WaiverAcceptance)
      assert acceptance.enrollment_id == enrollment.id
      assert acceptance.parent_id == parent.id
      assert acceptance.body_snapshot == version.body
      assert acceptance.user_agent == "TestBrowser/1.0"
    end

    test "submitting nothing ticked is refused", %{conn: conn, enrollment: enrollment} do
      {:ok, view, _html} = live(conn, ~p"/enrollments/#{enrollment.id}/waivers")

      html = view |> form("#sign-waivers-form", %{}) |> render_submit()

      assert html =~ "tick"
      assert Repo.aggregate(WaiverAcceptance, :count) == 0
    end

    test "an already-signed waiver shows as signed with no checkbox", %{
      conn: conn,
      enrollment: enrollment,
      parent: parent,
      version: version,
      waiver: waiver
    } do
      {:ok, _} = Enrollment.sign_waivers(enrollment.id, parent.id, [version.id], %{})

      {:ok, view, _html} = live(conn, ~p"/enrollments/#{enrollment.id}/waivers")

      assert has_element?(view, "#waiver-signed-#{waiver.id}")
      refute has_element?(view, "#sign-waiver-#{waiver.id}")
    end
  end
end
