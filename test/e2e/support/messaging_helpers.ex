defmodule KlassHeroWeb.E2E.MessagingHelpers do
  @moduledoc """
  Thin helper layer for messaging E2E tests.

  Centralizes DOM selectors, common multi-step browser interactions,
  and shared test data setup so tests stay readable without premature
  Page Object abstraction.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]
  use Wallaby.DSL

  import ExUnit.Callbacks, only: [start_supervised!: 1]
  import KlassHero.AccountsFixtures
  import KlassHero.Factory

  alias KlassHero.Accounts.Scope
  alias KlassHero.Messaging
  alias KlassHero.Messaging.Adapters.Driven.Projections.ConversationSummaries

  # --- Test data setup ---

  @doc """
  Creates a direct conversation between a provider and parent, with an initial message.

  Starts the ConversationSummaries projection, creates confirmed users with
  passwords and profiles, sends a seed message, and rebuilds the read model.

  Returns a map with `:provider_user`, `:parent_user`, `:provider`, and `:conversation`.
  """
  def setup_dm_conversation(initial_message \\ "Hello! Welcome to the program.") do
    start_supervised!(ConversationSummaries)

    provider_user = user_fixture(%{intended_roles: [:provider]}) |> set_password()

    provider =
      insert(:provider_profile_schema, identity_id: provider_user.id)

    parent_user = user_fixture(%{intended_roles: [:parent]}) |> set_password()

    insert(:parent_profile_schema,
      identity_id: parent_user.id,
      subscription_tier: "active"
    )

    provider_scope = Scope.for_user(provider_user) |> Scope.resolve_roles()

    {:ok, conversation} =
      Messaging.create_direct_conversation(provider_scope, provider.id, parent_user.id)

    {:ok, _message} =
      Messaging.send_message(conversation.id, provider_user.id, initial_message)

    rebuild_summaries()

    %{
      provider_user: provider_user,
      parent_user: parent_user,
      provider: provider,
      conversation: conversation
    }
  end

  @doc """
  Rebuilds the ConversationSummaries CQRS read model.

  Test event publishers don't use PubSub, so the projection needs
  explicit rebuilds after data mutations to reflect changes in
  conversation lists and unread counts.
  """
  def rebuild_summaries do
    ConversationSummaries.rebuild()
  end

  @doc """
  Waits for a browser-initiated DB write to commit, then rebuilds summaries.

  Use after browser actions (send_message, mark_as_read) that trigger
  server-side writes — the DB commit may not be visible to the
  projection immediately.
  """
  def wait_and_rebuild_summaries(ms \\ 500) do
    Process.sleep(ms)
    rebuild_summaries()
  end

  # --- Browser session helpers ---

  @doc """
  Starts a new Wallaby browser session with Ecto sandbox metadata attached.

  The metadata allows the browser's HTTP requests to share the test
  process's database transaction via the Phoenix.Ecto.SQL.Sandbox plug.
  """
  def new_session(metadata) do
    {:ok, session} = Wallaby.start_session(metadata: metadata)
    session
  end

  @doc """
  Logs in through the UI as the given user.

  Navigates to the login page, toggles to the password form,
  fills in credentials, and submits. The user must have had
  `AccountsFixtures.set_password/1` called on them.
  """
  def log_in(session, %{email: email}) do
    session = visit(session, "/users/log-in")
    session = click(session, Query.button("Or use password"))

    assert_has(session, Query.css("#login_form_password"))

    session =
      session
      |> fill_in(Query.css("#login_form_password_email"), with: email)
      |> fill_in(Query.css("#login_form_password_password"), with: valid_user_password())
      |> click(Query.css("#login_form_password button[name='user[remember_me]']"))

    # The login form uses phx-trigger-action: after the LiveView event sets
    # trigger_submit=true, the client JS submits an HTTP POST, the server
    # creates a session and redirects. This multi-step round-trip can race
    # with subsequent navigation. Poll until the URL changes away from the
    # login page, indicating the redirect has completed and the session
    # cookie has been set.
    wait_for_login_redirect(session)
  end

  defp wait_for_login_redirect(session, attempts \\ 0)

  defp wait_for_login_redirect(_session, 20) do
    raise "Login redirect did not complete within 5 seconds"
  end

  defp wait_for_login_redirect(session, attempts) do
    url = Wallaby.Browser.current_url(session)

    if String.contains?(url, "/users/log-in") do
      :timer.sleep(250)
      wait_for_login_redirect(session, attempts + 1)
    else
      session
    end
  end

  # --- DOM interaction helpers ---

  @doc """
  Sends a message in the current conversation view.
  """
  def send_message(session, text) do
    session
    |> fill_in(Query.css("#message-input"), with: text)
    |> click(Query.css("[data-role=send-message-btn]"))
  end

  @doc """
  Asserts that a message with the given text is visible in the conversation.
  """
  def assert_message_visible(session, text) do
    assert_has(session, Query.css("[data-role=message]", text: text))
  end

  @doc """
  Asserts the unread count badge shows the expected number.
  """
  def assert_unread_count(session, count) do
    assert_has(session, Query.css("[data-role=unread-count]", text: to_string(count)))
  end

  @doc """
  Asserts no unread count badge is visible.
  """
  def refute_unread_count(session) do
    refute_has(session, Query.css("[data-role=unread-count]"))
  end

  @doc """
  Navigates to the conversation list for the given role.
  """
  def visit_conversations(session, :provider), do: visit(session, "/provider/messages")
  def visit_conversations(session, :parent), do: visit(session, "/messages")

  @doc """
  Opens a conversation by clicking its card with matching text.
  """
  def open_conversation(session, name) do
    click(session, Query.css("[data-role=conversation-card]", text: name))
  end
end
