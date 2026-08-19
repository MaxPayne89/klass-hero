defmodule KlassHeroWeb.BookingLiveWaiversTest do
  @moduledoc """
  Waiver signing inside the self-serve booking form.

  The gate itself is covered in `create_enrollment_waivers_test.exs`; this file covers what
  the parent sees and what the form sends.
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

    %{provider: provider, program: program, parent: parent, child: child}
  end

  defp add_waiver(provider, program, opts) do
    {:ok, %{waiver: waiver, version: version}} =
      Enrollment.create_waiver(provider.id, %{
        program_id: program.id,
        title: Keyword.get(opts, :title, "Liability Waiver"),
        required: Keyword.get(opts, :required, true),
        body: Keyword.get(opts, :body, "I agree to hold the provider harmless.")
      })

    {waiver, version}
  end

  test "shows the waiver text and a sign checkbox", %{conn: conn, provider: provider, program: program} do
    {waiver, _version} = add_waiver(provider, program, [])

    {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}/booking")

    assert has_element?(view, "#waiver-#{waiver.id}")
    assert has_element?(view, "#sign-waiver-#{waiver.id}")
    assert render(view) =~ "I agree to hold the provider harmless."
  end

  test "renders no waiver section when the program has none", %{conn: conn, program: program} do
    {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}/booking")

    refute has_element?(view, "#booking-waivers")
  end

  test "submitting without signing a required waiver is refused and creates nothing", %{
    conn: conn,
    provider: provider,
    program: program,
    child: child
  } do
    add_waiver(provider, program, [])

    {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}/booking")

    html =
      view
      |> form("#booking-form", %{"child_id" => child.id, "special_requirements" => ""})
      |> render_submit()

    assert html =~ "waiver"
    assert Repo.aggregate(WaiverAcceptance, :count) == 0
  end

  test "signing the required waiver enrolls and records the acceptance", %{
    conn: conn,
    provider: provider,
    program: program,
    child: child,
    parent: parent
  } do
    {waiver, version} = add_waiver(provider, program, [])

    # The test client sends no User-Agent of its own, so set one — otherwise the audit
    # assertion below would pass vacuously against a nil the harness produced.
    conn = Plug.Conn.put_req_header(conn, "user-agent", "TestBrowser/1.0")

    {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}/booking")

    view
    |> form("#booking-form", %{
      "child_id" => child.id,
      "special_requirements" => "",
      "waiver_version_ids" => [version.id]
    })
    |> render_submit()

    assert_redirect(view, ~p"/dashboard")

    assert [acceptance] = Repo.all(WaiverAcceptance)
    assert acceptance.waiver_id == waiver.id
    assert acceptance.parent_id == parent.id
    assert acceptance.body_snapshot == version.body
    assert acceptance.user_agent == "TestBrowser/1.0"
  end

  test "an optional waiver does not block submission", %{
    conn: conn,
    provider: provider,
    program: program,
    child: child
  } do
    add_waiver(provider, program, required: false, title: "Photo release")

    {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}/booking")

    view
    |> form("#booking-form", %{"child_id" => child.id, "special_requirements" => ""})
    |> render_submit()

    assert_redirect(view, ~p"/dashboard")
    assert Repo.aggregate(WaiverAcceptance, :count) == 0
  end
end
