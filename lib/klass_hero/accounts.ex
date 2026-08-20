defmodule KlassHero.Accounts do
  @moduledoc """
  The Accounts context.
  """

  use KlassHero.Shared.Tracing

  import Ecto.Query, warn: false

  alias KlassHero.Accounts.Events
  alias KlassHero.Accounts.{PersonaGrant, User, UserNotifier, UserToken}
  alias KlassHero.Provider
  alias KlassHero.Provider.StaffMember
  alias KlassHero.Repo
  alias KlassHero.Shared.Outbox

  require Logger

  @doc """
  Registers a user.
  """
  def register_user(attrs) do
    context_span entity: "user" do
      register(attrs, &User.registration_changeset/2)
    end
  end

  @doc """
  Registers a new staff provider user via invitation.

  Uses staff_registration_changeset which locks intended_roles to [:staff].
  """
  def register_staff_user(attrs) do
    context_span entity: "user" do
      register(attrs, &User.staff_registration_changeset/2)
    end
  end

  defp register(attrs, changeset_fn) when is_map(attrs) do
    Outbox.transact(__MODULE__, fn ->
      with {:ok, user} <- %User{} |> changeset_fn.(attrs) |> Repo.insert() do
        {:ok, user, [Events.user_registered(user, %{registration_source: "web"})]}
      end
    end)
  end

  @doc """
  Links an existing, authenticated user to a staff invitation (#967).

  Appends `:staff` to the user's roles and links the StaffMember, only when the
  user's email matches the invite. `user` must come from the session, never params.

  Returns `{:ok, %User{}}`, `{:error, :email_mismatch}`, or an error from the
  underlying writes.
  """
  @spec link_staff_invitation(User.t(), StaffMember.t()) ::
          {:ok, User.t()} | {:error, :email_mismatch | term()}
  def link_staff_invitation(%User{} = user, %StaffMember{} = staff_member) do
    context_span entity: "user" do
      with :ok <- ensure_email_match(user, staff_member),
           {:ok, {updated_user, _linked}} <-
             PersonaGrant.grant(user, :staff, fn fresh_user ->
               Provider.accept_staff_invitation(staff_member, fresh_user.id)
             end) do
        {:ok, updated_user}
      end
    end
  end

  defp ensure_email_match(%User{email: user_email}, %StaffMember{email: invite_email}) do
    if emails_match?(user_email, invite_email), do: :ok, else: {:error, :email_mismatch}
  end

  @doc """
  Upgrades an existing, authenticated user to Provider (#968, ADR-0005).

  Creates a draft ProviderProfile for the user's identity and appends
  `:provider` to their roles, atomically. `user` must come from the session,
  never params — provider-hood is a deliberate, person-initiated act.

  Returns `{:ok, %User{}}`, `{:error, :already_provider}`, or an error from
  the underlying writes. The race where another request creates the profile
  between the pre-check and the insert is normalized from the unique-index
  backstop (`:duplicate_resource`) to `:already_provider`.
  """
  @spec upgrade_to_provider(User.t()) :: {:ok, User.t()} | {:error, :already_provider | term()}
  def upgrade_to_provider(%User{} = user) do
    context_span entity: "user" do
      if Provider.has_provider_profile?(user.id) do
        {:error, :already_provider}
      else
        user
        |> PersonaGrant.grant(:provider, fn fresh_user ->
          Provider.create_draft_provider_profile(fresh_user.id, fresh_user.name, fresh_user.email)
        end)
        |> normalize_upgrade_result()
      end
    end
  end

  defp normalize_upgrade_result({:ok, {updated_user, _profile}}), do: {:ok, updated_user}
  # Race loser hit the unique-index backstop: same condition as the pre-check.
  defp normalize_upgrade_result({:error, :duplicate_resource}), do: {:error, :already_provider}
  defp normalize_upgrade_result({:error, reason}), do: {:error, reason}

  @doc """
  Adds the user as a staff member of their OWN business (#969, ADR-0005).

  Creates a pre-linked, accepted staff row (no invitation) and appends `:staff`
  to their roles, atomically. `staff_attrs` takes the staff-form fields
  (`:first_name`, `:last_name`, `:role`, `:bio`, `:tags`, `:qualifications`,
  `:headshot_url`, `:pay_rate`); `:email` is forced to the account email.
  `user` must come from the session, never params.

  Returns `{:ok, %User{}, %StaffMember{}}`, `{:error, :not_a_provider}`,
  `{:error, :already_staffed}`, or an error from the underlying writes.
  """
  @spec add_self_as_staff(User.t(), map()) ::
          {:ok, User.t(), StaffMember.t()} | {:error, :not_a_provider | :already_staffed | term()}
  def add_self_as_staff(%User{} = user, staff_attrs) when is_map(staff_attrs) do
    case Provider.get_provider_by_identity(user.id) do
      {:ok, provider} -> grant_self_staff(user, provider, staff_attrs)
      {:error, :not_found} -> {:error, :not_a_provider}
    end
  end

  defp grant_self_staff(user, provider, staff_attrs) do
    with {:ok, {updated_user, staff}} <-
           PersonaGrant.grant(user, :staff, fn fresh_user ->
             attrs = Map.put(staff_attrs, :email, fresh_user.email)
             Provider.create_self_staff_member(provider.id, fresh_user.id, attrs)
           end) do
      {:ok, updated_user, staff}
    end
  end

  @doc """
  Ends a staff member's employment, atomically tearing down the now-backing-less
  `:staff` role (ADR-0005, #972).

  Provider offboards the person — retiring every program assignment so Messaging
  drops them from those conversations (#1292) — and Accounts settles the persona.
  `:staff` is removed from the linked user only when no other active linked staff
  row remains for them; multi-employer users keep it, and unlinked display-only
  rows never touch roles.

  Returns `{:ok, %StaffMember{}}` (the offboarded row) or `{:error, :not_found}`.
  """
  @spec offboard_staff_member(String.t(), String.t()) ::
          {:ok, StaffMember.t()} | {:error, :not_found}
  def offboard_staff_member(provider_id, staff_id) when is_binary(provider_id) and is_binary(staff_id) do
    context_span entity: "user" do
      Repo.transaction(fn ->
        # The fetch is the provider-scoping step — foreign ≡ missing — and supplies
        # the struct the offboard command takes.
        with {:ok, staff} <- Provider.get_staff_member(staff_id, provider_id),
             {:ok, %{staff_member: offboarded}} <- Provider.offboard_staff_member(staff),
             # Runs after the `active` flip, in the same transaction, so the
             # "any employment left?" query already sees this one as ended.
             :ok <- maybe_revoke_staff_role(offboarded) do
          offboarded
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
  end

  @doc """
  Erases a staff row that never became anything — the narrow counterpart to
  `offboard_staff_member/2` (#1292).

  Refuses with `{:error, :has_history}` unless the row has no linked user, no
  invitation ever sent, and no program assignment ever created; `Provider` owns
  that precondition. Use it for a roster entry typed in by mistake, never to
  remove someone who worked here.

  Returns `{:ok, %StaffMember{}}` (the deleted row) or
  `{:error, :not_found | :has_history}`.
  """
  @spec remove_staff_member(String.t(), String.t()) ::
          {:ok, StaffMember.t()} | {:error, :not_found | :has_history}
  def remove_staff_member(provider_id, staff_id) when is_binary(provider_id) and is_binary(staff_id) do
    context_span entity: "user" do
      Repo.transaction(fn ->
        # The fetch supplies the struct the caller gets back and the role teardown
        # needs; the delete is independently provider-scoped, so neither step can
        # reach a foreign row.
        with {:ok, staff} <- Provider.get_staff_member(staff_id, provider_id),
             :ok <- Provider.delete_staff_member(staff_id, provider_id),
             :ok <- maybe_revoke_staff_role(staff) do
          staff
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
  end

  # Unlinked display-only row — no persona to tear down
  defp maybe_revoke_staff_role(%StaffMember{user_id: nil}), do: :ok

  defp maybe_revoke_staff_role(%StaffMember{user_id: user_id}) do
    # Queried after the employment ended (same txn): :not_found means this was the last one
    case Provider.get_active_staff_member_by_user(user_id) do
      {:ok, _still_employed} -> :ok
      {:error, :not_found} -> revoke_staff(user_id)
    end
  end

  defp revoke_staff(user_id) do
    case Repo.get(User, user_id) do
      # Re-fetched inside the txn as a lost-update guard (mirrors PersonaGrant)
      %User{} = user ->
        with {:ok, _updated} <- user |> User.remove_role_changeset(:staff) |> Repo.update(), do: :ok

      nil ->
        :ok
    end
  end

  @doc """
  Emits a `staff_user_registered` integration event.

  Called after a successful `register_staff_user/1` (or when linking an
  existing user invited as staff). The caller knows the staff context
  (staff_member_id, provider_id) that the use case layer does not.

  Drives staff linkage only — the Provider context links the User to the
  StaffMember and accepts the invitation. Per ADR-0005 it never creates a
  ProviderProfile; provider-hood is a deliberate, separate act.

  Returns `:ok` on success or `{:error, reason}` on publish failure.
  """
  @spec emit_staff_user_registered(String.t(), String.t(), String.t()) ::
          :ok | {:error, term()}
  def emit_staff_user_registered(user_id, staff_member_id, provider_id)
      when is_binary(user_id) and is_binary(staff_member_id) and is_binary(provider_id) do
    user_id
    |> Events.staff_user_registered(%{
      staff_member_id: staff_member_id,
      provider_id: provider_id
    })
    |> then(&Outbox.stage(__MODULE__, &1))
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.

  Returns `{:ok, %User{}}`, `{:error, :invalid_token}`, or `{:error, %Ecto.Changeset{}}`.
  """
  def update_user_email(%User{} = user, token) when is_binary(token) do
    context_span entity: "user" do
      apply_email_change(user, token)
    end
  end

  # Applies a verified email-change token atomically: verify, fetch the address
  # the token was sent to, swap it in, then invalidate the change tokens.
  defp apply_email_change(%User{} = user, token) do
    context = "change:#{user.email}"

    Ecto.Multi.new()
    |> Ecto.Multi.run(:verify_token, fn _repo, _ ->
      # verify_change_email_token_query returns bare :error for bad base64; normalize to tagged tuple
      case UserToken.verify_change_email_token_query(token, context) do
        {:ok, query} -> {:ok, query}
        :error -> {:error, :invalid_token}
      end
    end)
    |> Ecto.Multi.run(:fetch_token, fn repo, %{verify_token: query} ->
      case repo.one(query) do
        %UserToken{sent_to: email} = token_record -> {:ok, {token_record, email}}
        nil -> {:error, :token_not_found}
      end
    end)
    |> Ecto.Multi.run(:update_email, fn repo, %{fetch_token: {_token_record, email}} ->
      user
      |> User.email_changeset(%{email: email})
      |> repo.update()
    end)
    |> Ecto.Multi.delete_all(:delete_tokens, fn %{update_email: updated_user} ->
      from(UserToken, where: [user_id: ^updated_user.id, context: ^context])
    end)
    |> Repo.transaction()
    |> normalize_email_change_result()
  end

  defp normalize_email_change_result({:ok, %{update_email: updated_user}}), do: {:ok, updated_user}

  defp normalize_email_change_result({:error, step, _reason, _}) when step in [:verify_token, :fetch_token],
    do: {:error, :invalid_token}

  defp normalize_email_change_result({:error, _step, reason, _}), do: {:error, reason}

  @doc """
  Updates the user password.

  Returns `{:ok, {%User{}, expired_tokens}}` or `{:error, %Ecto.Changeset{}}`.
  """
  def update_user_password(user, attrs) do
    context_span entity: "user" do
      user
      |> User.password_changeset(attrs)
      |> update_user_and_delete_all_tokens()
    end
  end

  @doc """
  Updates the user password, requiring sudo mode.

  Returns `{:error, :sudo_required}` if not in sudo mode; otherwise behaves like `update_user_password/2`.
  """
  def update_user_password_with_sudo(user, attrs) do
    if sudo_mode?(user) do
      update_user_password(user, attrs)
    else
      {:error, :sudo_required}
    end
  end

  @doc """
  Updates the user locale preference.
  """
  def update_user_locale(user, attrs) do
    context_span entity: "user" do
      user
      |> User.locale_changeset(attrs)
      |> Repo.update()
    end
  end

  @doc """
  Remembers the surface this user last chose to work in (ADR-0005).

  A preference, not a grant: the caller is responsible for having checked that
  the user actually holds the persona before asking to store it. Passing `nil`
  clears the preference and returns them to precedence-based landing.
  """
  @spec update_user_active_persona(User.t(), map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_user_active_persona(user, attrs) do
    context_span entity: "user" do
      user
      |> User.active_persona_changeset(attrs)
      |> Repo.update()
    end
  end

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.

  Returns `{:ok, {%User{}, expired_tokens}}`, `{:error, :not_found}`,
  `{:error, :invalid_token}`, or `{:error, :security_violation}`.
  """
  def login_user_by_magic_link(token) when is_binary(token) do
    context_span entity: "user" do
      case resolve_magic_link(token) do
        {:ok, {:unconfirmed, user}} ->
          confirm_magic_link_login(user)

        {:ok, {:confirmed, user, token_record}} ->
          delete_magic_link_token(token_record)
          {:ok, {user, []}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp resolve_magic_link(token) do
    # verify_magic_link_token_query returns bare :error for bad base64; normalize to tagged tuple
    case UserToken.verify_magic_link_token_query(token) do
      {:ok, query} -> resolve_magic_link_query(Repo.one(query))
      :error -> {:error, :invalid_token}
    end
  end

  # Unconfirmed user with a password set — reject to prevent session fixation via magic link
  defp resolve_magic_link_query({%User{confirmed_at: nil, hashed_password: hash}, _token}) when not is_nil(hash) do
    {:error, :security_violation}
  end

  # Unconfirmed user without password — first login; confirmation handled below
  defp resolve_magic_link_query({%User{confirmed_at: nil} = user, _token}) do
    {:ok, {:unconfirmed, user}}
  end

  defp resolve_magic_link_query({user, token}), do: {:ok, {:confirmed, user, token}}
  defp resolve_magic_link_query(nil), do: {:error, :not_found}

  # First login for unconfirmed user: confirm email, expire all tokens, dispatch event
  defp confirm_magic_link_login(user) do
    Outbox.transact(__MODULE__, fn ->
      with {:ok, {confirmed_user, tokens}} <-
             user |> User.confirm_changeset() |> update_user_and_delete_all_tokens() do
        event = Events.user_confirmed(confirmed_user, %{confirmation_method: "magic_link"})
        {:ok, {confirmed_user, tokens}, [event]}
      end
    end)
  end

  defp delete_magic_link_token(%UserToken{} = token) do
    case Repo.delete(token) do
      {:ok, _} ->
        :ok

      # Constraint failure: log for visibility but treat as success — token is invalidated either way
      {:error, changeset} ->
        Logger.warning("Token deletion failed: #{inspect(changeset)}")
        :ok
    end
  rescue
    # Concurrent delete: Repo.delete raises StaleEntryError when row is already gone
    Ecto.StaleEntryError -> :ok
  end

  @doc """
  Delivers the update email instructions to the given user.
  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    token = issue_email_token(user, "change:#{current_email}")
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun) when is_function(magic_link_url_fun, 1) do
    token = issue_email_token(user, "login")
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(token))
  end

  @doc """
  Generates a magic link login token for a user without sending an email.

  Used by the invite claim flow where the redirect URL is built directly
  rather than delivered via email.

  Returns the URL-safe encoded token string.
  """
  def generate_magic_link_token(%User{} = user), do: issue_email_token(user, "login")

  # Persists a hashed email token and hands back the URL-safe half to send out.
  defp issue_email_token(user, context) do
    {encoded_token, user_token} = UserToken.build_email_token(user, context)
    Repo.insert!(user_token)
    encoded_token
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  @doc """
  Anonymizes a user account for GDPR deletion. Replaces PII, invalidates all tokens,
  and publishes `user_anonymized` for downstream cascade.
  """
  def anonymize_user(%User{} = user) do
    context_span entity: "user" do
      previous_email = user.email

      Outbox.transact(__MODULE__, fn ->
        with {:ok, anonymized_user} <- anonymize(user) do
          event = Events.user_anonymized(anonymized_user, %{previous_email: previous_email})
          {:ok, anonymized_user, [event]}
        end
      end)
    end
  end

  def anonymize_user(nil), do: {:error, :user_not_found}

  # Scrubs PII and invalidates every token in one transaction.
  defp anonymize(%User{} = user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:anonymize_user, User.anonymize_changeset(user))
    |> Ecto.Multi.delete_all(:delete_tokens, fn %{anonymize_user: anonymized_user} ->
      from(t in UserToken, where: t.user_id == ^anonymized_user.id)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{anonymize_user: user}} -> {:ok, user}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  @doc """
  Anonymizes user account after sudo-mode and password verification.

  Returns `{:ok, %User{}}`, `{:error, :sudo_required}`, `{:error, :invalid_password}`,
  or `{:error, reason}`.
  """
  def delete_account(%User{} = user, password) when is_binary(password) do
    with :ok <- check_delete_sudo(user),
         :ok <- check_delete_password(user, password) do
      anonymize_user(user)
    end
  end

  @doc """
  Gets a user by email.
  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Resolves display names for a batch of user IDs.

  Returns a map of `user_id => name`. Unknown IDs are omitted from the result.
  Used by other contexts (e.g. Messaging) that need human-readable
  sender/participant names without reaching into the `User` schema.
  """
  @spec get_display_names([String.t()]) :: %{String.t() => String.t()}
  def get_display_names([]), do: %{}

  def get_display_names(user_ids) when is_list(user_ids) do
    from(u in User, where: u.id in ^user_ids, select: {u.id, u.name})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Resolves a single user's display name.
  """
  @spec get_display_name(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def get_display_name(user_id) do
    case get_display_names([user_id]) do
      %{^user_id => name} -> {:ok, name}
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Returns true when two emails refer to the same address (case- and
  whitespace-insensitive). Single source of truth for the staff-invite
  link match — both the accept screen and `link_staff_invitation/2` use it.
  """
  @spec emails_match?(String.t() | nil, String.t() | nil) :: boolean()
  def emails_match?(a, b), do: normalize_email(a) == normalize_email(b) and not is_nil(a)

  @doc "Normalizes an email for comparison (trim + downcase). `nil` stays `nil`."
  @spec normalize_email(String.t() | nil) :: String.t() | nil
  def normalize_email(nil), do: nil
  def normalize_email(email) when is_binary(email), do: email |> String.trim() |> String.downcase()

  @doc """
  Gets a user by email and password.
  """
  def get_user_by_email_and_password(email, password) when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user. Raises `Ecto.NoResultsError` if not found.
  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Exports all personal data for the given user in GDPR-compliant format.

  Returns a map containing all user data that can be serialized to JSON.
  """
  def export_user_data(%User{} = user) do
    %{
      exported_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      user: %{
        id: user.id,
        email: user.email,
        name: user.name,
        avatar: user.avatar,
        confirmed_at: user.confirmed_at && DateTime.to_iso8601(user.confirmed_at),
        created_at: user.inserted_at && DateTime.to_iso8601(user.inserted_at),
        updated_at: user.updated_at && DateTime.to_iso8601(user.updated_at)
      }
    }
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user registration changes.
  """
  def change_user_registration(user, attrs \\ %{}, opts \\ []) do
    User.registration_changeset(user, attrs, opts)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking staff registration changes.

  Uses `staff_registration_changeset` which locks intended_roles to
  `[:staff]`.
  """
  def change_staff_registration(attrs, opts \\ []) do
    User.staff_registration_changeset(%User{}, attrs, opts)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `KlassHero.Accounts.User.email_changeset/3` for supported options.
  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `KlassHero.Accounts.User.password_changeset/3` for supported options.
  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user locale.
  """
  def change_user_locale(user, attrs \\ %{}) do
    User.locale_changeset(user, attrs)
  end

  # Updates a user via changeset and deletes all their tokens atomically.
  # Returns `{:ok, {user, deleted_tokens}}` or `{:error, changeset}` — the
  # deleted tokens are returned so callers can invalidate live sessions.
  defp update_user_and_delete_all_tokens(changeset) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:update_user, changeset)
    |> Ecto.Multi.run(:fetch_tokens, fn repo, %{update_user: user} ->
      {:ok, repo.all_by(UserToken, user_id: user.id)}
    end)
    |> Ecto.Multi.delete_all(:delete_tokens, fn %{fetch_tokens: tokens} ->
      from(t in UserToken, where: t.id in ^Enum.map(tokens, & &1.id))
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{update_user: user, fetch_tokens: tokens}} -> {:ok, {user, tokens}}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  defp check_delete_sudo(user) do
    if sudo_mode?(user), do: :ok, else: {:error, :sudo_required}
  end

  defp check_delete_password(user, password) do
    if User.valid_password?(user, password), do: :ok, else: {:error, :invalid_password}
  end
end
