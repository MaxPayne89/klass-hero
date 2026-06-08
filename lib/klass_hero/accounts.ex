defmodule KlassHero.Accounts do
  @moduledoc """
  The Accounts context.
  """

  use Boundary,
    top_level?: true,
    deps: [KlassHero, KlassHero.Family, KlassHero.Provider, KlassHero.Shared],
    exports: [Scope, User, UserNotifier]

  import Ecto.Query, warn: false

  alias KlassHero.Accounts.Adapters.Driven.Persistence.TokenCleanup

  alias KlassHero.Accounts.Application.Commands.{
    AnonymizeUser,
    ChangeEmail,
    LoginByMagicLink,
    RegisterUser
  }

  alias KlassHero.Accounts.Application.Queries.ExportUserData
  alias KlassHero.Accounts.Domain.Events.AccountsIntegrationEvents
  alias KlassHero.Accounts.{User, UserNotifier, UserToken}
  alias KlassHero.Repo
  alias KlassHero.Shared.IntegrationEventPublishing

  # ===========================================================================
  # Commands
  # ===========================================================================

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    RegisterUser.execute(attrs)
  end

  @doc """
  Registers a new staff provider user via invitation.

  Uses staff_registration_changeset which locks intended_roles to [:staff].
  """
  def register_staff_user(attrs) do
    RegisterUser.execute(attrs, changeset_fn: &User.staff_registration_changeset/2)
  end

  @doc """
  Emits a `staff_user_registered` integration event.

  Called by the invitation registration LiveView after a successful
  `register_staff_user/1`. The LiveView knows the staff context
  (staff_member_id, provider_id) that the use case layer does not.

  ## Options (4th argument, optional map)

  - `create_provider_profile: true` — signals the Provider context to
    create a provider profile for this user.
  - `user_name` — used as the default business name for the provider profile.

  Returns `:ok` on success or `{:error, reason}` on publish failure.
  """
  @spec emit_staff_user_registered(String.t(), String.t(), String.t(), map()) ::
          :ok | {:error, term()}
  def emit_staff_user_registered(user_id, staff_member_id, provider_id, opts \\ %{})

  def emit_staff_user_registered(user_id, staff_member_id, provider_id, opts)
      when is_binary(user_id) and is_binary(staff_member_id) and is_binary(provider_id) do
    payload =
      opts
      |> Map.merge(%{staff_member_id: staff_member_id, provider_id: provider_id})

    user_id
    |> AccountsIntegrationEvents.staff_user_registered(payload)
    |> IntegrationEventPublishing.publish_critical("staff_user_registered",
      user_id: user_id,
      staff_member_id: staff_member_id
    )
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    ChangeEmail.execute(user, token)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> TokenCleanup.update_user_and_delete_all_tokens()
  end

  @doc """
  Updates the user password, requiring sudo mode.

  Returns `{:error, :sudo_required}` if user is not in sudo mode.
  Otherwise behaves like `update_user_password/2`.

  ## Examples

      iex> update_user_password_with_sudo(user_in_sudo_mode, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password_with_sudo(user_not_in_sudo_mode, %{password: ...})
      {:error, :sudo_required}

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

  ## Examples

      iex> update_user_locale(user, %{locale: "de"})
      {:ok, %User{locale: "de"}}

      iex> update_user_locale(user, %{locale: "invalid"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_locale(user, attrs) do
    user
    |> User.locale_changeset(attrs)
    |> Repo.update()
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
  """
  def login_user_by_magic_link(token) do
    LoginByMagicLink.execute(token)
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun) when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Generates a magic link login token for a user without sending an email.

  Used by the invite claim flow where the redirect URL is built directly
  rather than delivered via email.

  Returns the URL-safe encoded token string.
  """
  def generate_magic_link_token(%User{} = user) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
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
  Anonymizes a user account for GDPR deletion requests.

  This function:
  1. Stores the previous email for audit trail
  2. Invalidates all session tokens (logs out from all devices)
  3. Replaces PII with anonymized values
  4. Publishes `user_anonymized` domain event

  Downstream contexts (Identity, Participation) react to the `user_anonymized`
  event asynchronously to anonymize their own data.

  ## Examples

      iex> anonymize_user(user)
      {:ok, %User{email: "deleted_123@anonymized.local"}}

      iex> anonymize_user(nil)
      {:error, :user_not_found}

  """
  def anonymize_user(%User{} = user) do
    AnonymizeUser.execute(user)
  end

  def anonymize_user(nil), do: {:error, :user_not_found}

  @doc """
  Deletes (anonymizes) user account after password verification.

  This function orchestrates the complete account deletion flow:
  1. Verifies user is in sudo mode
  2. Verifies password matches
  3. Anonymizes the user account

  ## Returns

    * `{:ok, %User{}}` - Account successfully anonymized
    * `{:error, :sudo_required}` - User is not in sudo mode
    * `{:error, :invalid_password}` - Password doesn't match
    * `{:error, reason}` - Anonymization failed

  ## Examples

      iex> delete_account(user_in_sudo_mode, "correct_password")
      {:ok, %User{email: "deleted_123@anonymized.local"}}

      iex> delete_account(user_not_in_sudo_mode, "password")
      {:error, :sudo_required}

      iex> delete_account(user_in_sudo_mode, "wrong_password")
      {:error, :invalid_password}

  """
  def delete_account(%User{} = user, password) when is_binary(password) do
    with :ok <- check_delete_sudo(user),
         :ok <- check_delete_password(user, password) do
      AnonymizeUser.execute(user)
    end
  end

  # ===========================================================================
  # Queries
  # ===========================================================================

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password) when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

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
    ExportUserData.execute(user)
  end

  # ===========================================================================
  # Forms
  # ===========================================================================

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user registration changes.

  ## Examples

      iex> change_user_registration(user)
      %Ecto.Changeset{data: %User{}}

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

  See `KlassHero.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `KlassHero.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user locale.

  ## Examples

      iex> change_user_locale(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_locale(user, attrs \\ %{}) do
    User.locale_changeset(user, attrs)
  end

  # ===========================================================================
  # Private
  # ===========================================================================

  # Trigger: user's last authentication is older than sudo timeout
  # Why: sudo mode prevents account deletion without recent auth
  # Outcome: returns :ok or {:error, :sudo_required}
  defp check_delete_sudo(user) do
    if sudo_mode?(user), do: :ok, else: {:error, :sudo_required}
  end

  defp check_delete_password(user, password) do
    if User.valid_password?(user, password), do: :ok, else: {:error, :invalid_password}
  end
end
