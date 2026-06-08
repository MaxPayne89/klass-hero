defmodule KlassHeroWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use KlassHeroWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]
  use ExUnit.CaseTemplate

  alias KlassHero.Accounts.Scope
  alias KlassHero.AccountsFixtures

  using do
    quote do
      use KlassHeroWeb, :verified_routes

      import KlassHeroWeb.ConnCase
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import Plug.Conn

      # The default endpoint for testing
      @endpoint KlassHeroWeb.Endpoint

      # Import conveniences for testing with connections
    end
  end

  setup tags do
    KlassHero.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Asserts that a LiveView has a flash message of the given kind.

  ## Examples

      assert_flash(lv, :info, "Success")
      assert_flash(lv, :error, ~r/Invalid/)
  """
  def assert_flash(lv, kind, expected) do
    flash = :sys.get_state(lv.pid).socket.assigns.flash

    actual = Phoenix.Flash.get(flash, kind)

    cond do
      is_nil(actual) ->
        flunk("Expected flash #{inspect(kind)} to be set, but it was nil. Flash: #{inspect(flash)}")

      is_binary(expected) and actual == expected ->
        true

      is_struct(expected, Regex) and actual =~ expected ->
        true

      is_binary(expected) ->
        flunk("""
        Expected flash #{inspect(kind)} to equal:
          #{inspect(expected)}
        but got:
          #{inspect(actual)}
        """)

      true ->
        flunk("""
        Expected flash #{inspect(kind)} to match:
          #{inspect(expected)}
        but got:
          #{inspect(actual)}
        """)
    end
  end

  @doc """
  Setup helper that registers and logs in users.

      setup :register_and_log_in_user

  It stores an updated connection and a registered user in the
  test context.
  """
  def register_and_log_in_user(%{conn: conn} = context) do
    user = AccountsFixtures.user_fixture()
    scope = Scope.for_user(user)

    opts =
      context
      |> Map.take([:token_authenticated_at])
      |> Enum.to_list()

    %{conn: log_in_user(conn, user, opts), user: user, scope: scope}
  end

  @doc """
  Logs the given `user` into the `conn`.

  It returns an updated `conn`.
  """
  def log_in_user(conn, user, opts \\ []) do
    token = KlassHero.Accounts.generate_user_session_token(user)

    maybe_set_token_authenticated_at(token, opts[:token_authenticated_at])

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end

  @doc """
  Setup helper that registers and logs in users, and creates a parent profile with a child.

      setup :register_and_log_in_user_with_child

  It stores an updated connection, registered user, parent profile, and child in the test context.
  This is useful for tests that require the user to have children (dashboard, booking, etc.)
  """
  def register_and_log_in_user_with_child(%{conn: _conn} = context) do
    result = register_and_log_in_user(context)

    # Create parent profile linked to the user
    parent = KlassHero.Factory.insert(:parent_schema, identity_id: result.user.id)

    # Create a child linked to the parent via guardian join table
    {child, _parent} =
      KlassHero.Factory.insert_child_with_guardian(parent: parent, first_name: "Emma")

    Map.merge(result, %{parent: parent, child: child})
  end

  @doc """
  Setup helper that registers and logs in users with a provider profile.

      setup :register_and_log_in_provider

  It stores an updated connection, registered user, and provider profile in the test context.
  This is useful for tests that require provider-only routes.
  """
  def register_and_log_in_provider(%{conn: _conn} = context) do
    user = AccountsFixtures.user_fixture(%{intended_roles: [:provider]})
    provider = KlassHero.Factory.insert(:provider_profile_schema, identity_id: user.id)

    scope = Scope.for_user(user) |> Scope.resolve_roles()

    %{conn: log_in_user(context.conn, user), user: user, scope: scope, provider: provider}
  end

  @doc """
  Setup helper that registers and logs in an admin user.

      setup :register_and_log_in_admin

  It stores an updated connection, registered admin user, and scope in the test context.
  This is useful for tests that require admin-only routes.
  """
  def register_and_log_in_admin(%{conn: _conn} = context) do
    user = AccountsFixtures.user_fixture(%{is_admin: true})
    scope = Scope.for_user(user)

    %{conn: log_in_user(context.conn, user), user: user, scope: scope}
  end

  @doc """
  Setup helper that registers and logs in users with a parent profile.

      setup :register_and_log_in_parent

  It stores an updated connection, registered user, and parent profile in the test context.
  This is useful for tests that require parent-only routes.
  """
  def register_and_log_in_parent(%{conn: _conn} = context) do
    user = AccountsFixtures.user_fixture(%{intended_roles: [:parent]})
    parent = KlassHero.Factory.insert(:parent_profile_schema, identity_id: user.id)

    scope = Scope.for_user(user) |> Scope.resolve_roles()

    %{conn: log_in_user(context.conn, user), user: user, scope: scope, parent: parent}
  end

  @doc """
  Setup helper that registers and logs in a staff member.

      setup :register_and_log_in_staff

  It stores an updated connection, registered user, provider, staff member, and scope
  in the test context. This is useful for tests that require staff-only routes.
  """
  def register_and_log_in_staff(%{conn: _conn} = context) do
    user = AccountsFixtures.user_fixture(%{intended_roles: [:staff]})
    provider = KlassHero.Factory.insert(:provider_profile_schema)

    staff =
      KlassHero.ProviderFixtures.staff_member_fixture(%{
        provider_id: provider.id,
        user_id: user.id,
        active: true,
        invitation_status: :accepted,
        tags: ["sports"]
      })

    scope = Scope.for_user(user) |> Scope.resolve_roles()

    %{
      conn: log_in_user(context.conn, user),
      user: user,
      scope: scope,
      provider: provider,
      staff: staff
    }
  end

  @doc """
  Setup helper that registers and logs in a dual-role user with a draft provider profile.

      setup :register_and_log_in_draft_provider

  Simulates a staff member who opted into provider role during activation.
  The provider profile is in draft status (needs completion).
  Includes a linked staff member with bio and tags for pre-fill testing.
  """
  def register_and_log_in_draft_provider(%{conn: _conn} = context) do
    user = AccountsFixtures.user_fixture(%{intended_roles: [:staff, :provider]})

    provider =
      KlassHero.Factory.insert(:draft_provider_profile_schema, identity_id: user.id)

    staff =
      KlassHero.ProviderFixtures.staff_member_fixture(%{
        provider_id: provider.id,
        user_id: user.id,
        active: true,
        invitation_status: :accepted,
        bio: "Experienced youth sports coach",
        tags: ["sports", "arts"],
        headshot_url: "https://example.com/headshot.jpg"
      })

    scope = Scope.for_user(user) |> Scope.resolve_roles()

    %{
      conn: log_in_user(context.conn, user),
      user: user,
      scope: scope,
      provider: provider,
      staff: staff
    }
  end

  defp maybe_set_token_authenticated_at(_token, nil), do: nil

  defp maybe_set_token_authenticated_at(token, authenticated_at) do
    AccountsFixtures.override_token_authenticated_at(token, authenticated_at)
  end
end
