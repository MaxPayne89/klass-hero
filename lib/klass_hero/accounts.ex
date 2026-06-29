defmodule KlassHero.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false

  alias KlassHero.Accounts.Adapters.Driven.Persistence.TokenCleanup

  alias KlassHero.Accounts.Application.Commands.{
    AddSelfAsStaff,
    AnonymizeUser,
    ChangeEmail,
    LinkStaffInvitation,
    LoginByMagicLink,
    RegisterUser,
    RemoveStaffMember,
    UpgradeToProvider
  }

  alias KlassHero.Accounts.Application.Queries.ExportUserData
  alias KlassHero.Accounts.Domain.Events.AccountsIntegrationEvents
  alias KlassHero.Accounts.{User, UserNotifier, UserToken}
  alias KlassHero.Provider.Domain.Models.StaffMember
  alias KlassHero.Repo
  alias KlassHero.Shared.IntegrationEventPublishing

  @doc """
  Registers a user.
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
  Links an existing, authenticated user to a staff invitation (#967).

  Appends `:staff` to the user's roles and links the StaffMember, only when the
  user's email matches the invite. `user` must come from the session, never params.

  Returns `{:ok, %User{}}`, `{:error, :email_mismatch}`, or an error from the
  underlying writes.
  """
  @spec link_staff_invitation(User.t(), StaffMember.t()) ::
          {:ok, User.t()} | {:error, :email_mismatch | term()}
  def link_staff_invitation(%User{} = user, %StaffMember{} = staff_member) do
    LinkStaffInvitation.execute(user, staff_member)
  end

  @doc """
  Upgrades an existing, authenticated user to Provider (#968, ADR-0005).

  Creates a draft ProviderProfile for the user's identity and appends
  `:provider` to their roles, atomically. `user` must come from the session,
  never params — provider-hood is a deliberate, person-initiated act.

  Returns `{:ok, %User{}}`, `{:error, :already_provider}`, or an error from
  the underlying writes.
  """
  @spec upgrade_to_provider(User.t()) :: {:ok, User.t()} | {:error, :already_provider | term()}
  def upgrade_to_provider(%User{} = user) do
    UpgradeToProvider.execute(user)
  end

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
          {:ok, User.t(), struct()} | {:error, :not_a_provider | :already_staffed | term()}
  def add_self_as_staff(%User{} = user, staff_attrs) when is_map(staff_attrs) do
    AddSelfAsStaff.execute(user, staff_attrs)
  end

  @doc """
  Deletes a staff member row, atomically tearing down the now-backing-less
  `:staff` role (ADR-0005, #972).

  `:staff` is removed from the linked user only when no other active linked staff
  row remains for them; multi-employer users keep it, and unlinked display-only
  rows never touch roles.

  Returns `{:ok, %StaffMember{}}` (the deleted row) or `{:error, :not_found}`.
  """
  @spec remove_staff_member(String.t()) :: {:ok, StaffMember.t()} | {:error, :not_found}
  def remove_staff_member(staff_id) when is_binary(staff_id) do
    RemoveStaffMember.execute(staff_id)
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
    |> AccountsIntegrationEvents.staff_user_registered(%{
      staff_member_id: staff_member_id,
      provider_id: provider_id
    })
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

  Returns `{:ok, {%User{}, expired_tokens}}` or `{:error, %Ecto.Changeset{}}`.
  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> TokenCleanup.update_user_and_delete_all_tokens()
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

  @doc """
  Delivers the update email instructions to the given user.
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
  Anonymizes a user account for GDPR deletion. Replaces PII, invalidates all tokens,
  and publishes `user_anonymized` for downstream cascade.
  """
  def anonymize_user(%User{} = user) do
    AnonymizeUser.execute(user)
  end

  def anonymize_user(nil), do: {:error, :user_not_found}

  @doc """
  Anonymizes user account after sudo-mode and password verification.

  Returns `{:ok, %User{}}`, `{:error, :sudo_required}`, `{:error, :invalid_password}`,
  or `{:error, reason}`.
  """
  def delete_account(%User{} = user, password) when is_binary(password) do
    with :ok <- check_delete_sudo(user),
         :ok <- check_delete_password(user, password) do
      AnonymizeUser.execute(user)
    end
  end

  @doc """
  Gets a user by email.
  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
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
    ExportUserData.execute(user)
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

  defp check_delete_sudo(user) do
    if sudo_mode?(user), do: :ok, else: {:error, :sudo_required}
  end

  defp check_delete_password(user, password) do
    if User.valid_password?(user, password), do: :ok, else: {:error, :invalid_password}
  end
end
