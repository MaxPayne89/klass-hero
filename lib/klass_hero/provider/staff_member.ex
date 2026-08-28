defmodule KlassHero.Provider.StaffMember do
  @moduledoc """
  Staff/team member of a provider (`staff_members` table).

  This module is both the Ecto schema and the struct consumers pattern-match.
  It carries three concerns that used to live in separate DDD layers:

    * **Persistence** — the Ecto schema + changesets (`create_changeset/2`,
      `edit_changeset/2`, `admin_changeset/3`, `invitation_changeset/2`), which
      are the validation gatekeeper at the DB boundary.
    * **Functional core** — pure business logic ported verbatim from the former
      domain model: the invitation state machine (`transition_invitation/2`),
      `full_name/1`, `initials/1`, `generate_invitation_token/0`,
      `invitation_expired?/1`, and the `new/1`/`valid?/1` domain validator that
      returns `{:error, [message]}` lists (the shape consumers key on).
    * **Pay rate** — a `%KlassHero.Provider.PayRate{}` value object stored flat as
      `rate_type`/`rate_amount`/`rate_currency`. Writes flatten it via
      `apply_pay_rate_struct/1`; reads rebuild it into the virtual `:pay_rate`
      field via `load_pay_rate/1`.

  ## Field naming

  `belongs_to :provider` keeps the struct field `provider_id` (the DB column),
  matching the frozen public-API struct shape. The association targets the
  still-DDD `ProviderProfile` (parked alias — repointed to the flattened
  `KlassHero.Provider.ProviderProfile` in Slice 5).
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  # Parked alias to the still-DDD ProviderProfile schema — repointed to the
  # flattened KlassHero.Provider.ProviderProfile in Slice 5.
  alias KlassHero.Provider.PayRate
  alias KlassHero.Provider.ProviderProfile
  alias KlassHero.Shared.Categories
  alias KlassHero.Shared.Money
  alias KlassHero.Shared.NameUtils

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  # State machine is the single source of truth for both the transitions and the
  # Ecto.Enum values (nil is the pre-invitation state, not an enum member).
  @valid_invitation_transitions %{
    nil => [:pending],
    :pending => [:sent, :failed, :accepted],
    :sent => [:accepted, :expired],
    :failed => [:pending],
    :expired => [:pending]
  }
  @invitation_statuses @valid_invitation_transitions
                       |> Map.values()
                       |> List.flatten()
                       |> Enum.uniq()

  @invitation_expiry_days 7

  schema "staff_members" do
    belongs_to :provider, ProviderProfile, type: :binary_id
    field :first_name, :string
    field :last_name, :string
    field :role, :string
    field :email, :string
    field :bio, :string
    field :headshot_url, :string
    field :tags, {:array, :string}, default: []
    field :qualifications, {:array, :string}, default: []
    field :active, :boolean, default: true
    field :invitation_status, Ecto.Enum, values: @invitation_statuses
    field :invitation_token_hash, :binary
    field :invitation_sent_at, :utc_datetime_usec
    field :user_id, :binary_id
    # Staff-context switcher (#969 finding 1): bumped only via
    # touch_last_selected/2 (update_all) — deliberately absent from every
    # changeset cast list so no form path can set or wipe it.
    field :last_selected_at, :utc_datetime_usec
    field :rate_type, Ecto.Enum, values: PayRate.valid_types()
    field :rate_amount, :decimal
    field :rate_currency, Ecto.Enum, values: Money.valid_currencies()
    # Virtual: hydrated from the three rate_* columns by load_pay_rate/1 so
    # consumers keep reading staff.pay_rate as a %PayRate{}.
    field :pay_rate, :any, virtual: true

    timestamps()
  end

  @type t :: %__MODULE__{}

  @pay_rate_fields [:rate_type, :rate_amount, :rate_currency]

  # ── Changesets (persistence gatekeeper) ──────────────────────────────────

  @doc """
  Changeset for creating a new staff member.

  `provider_id` and `user_id` are set programmatically via `put_change`, not cast
  from user input. `user_id` is only present for self-staffing (#969), where the
  row is born already linked. `Ecto.Enum` rejects invalid `invitation_status`
  values on cast, so no `validate_inclusion` is needed.
  """
  def create_changeset(schema \\ %__MODULE__{}, attrs) do
    attrs = apply_pay_rate_struct(attrs)
    provider_id = attrs[:provider_id] || attrs["provider_id"]
    user_id = attrs[:user_id] || attrs["user_id"]

    schema
    |> cast(attrs, [
      :first_name,
      :last_name,
      :role,
      :email,
      :bio,
      :headshot_url,
      :tags,
      :qualifications,
      :active,
      :invitation_status,
      :invitation_token_hash,
      :rate_type,
      :rate_amount,
      :rate_currency
    ])
    |> put_change(:provider_id, provider_id)
    |> maybe_put_user_id(user_id)
    |> validate_required([:provider_id, :first_name, :last_name])
    |> validate_length(:first_name, min: 1, max: 100)
    |> validate_length(:last_name, min: 1, max: 100)
    |> validate_length(:role, max: 100)
    |> validate_length(:email, max: 255)
    |> validate_length(:bio, max: 2000)
    |> validate_length(:headshot_url, max: 500)
    |> validate_tags()
    |> validate_pay_rate()
    |> foreign_key_constraint(:provider_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:provider_id, :user_id],
      name: :staff_members_active_provider_user_index,
      message: "already an active staff member of this provider"
    )
  end

  defp maybe_put_user_id(changeset, nil), do: changeset
  defp maybe_put_user_id(changeset, user_id), do: put_change(changeset, :user_id, user_id)

  @doc """
  Form changeset for editing staff members via LiveView.
  Excludes `provider_id` (set programmatically, immutable after creation).
  """
  def edit_changeset(schema, attrs) do
    attrs = apply_pay_rate_struct(attrs)

    schema
    |> cast(attrs, [
      :first_name,
      :last_name,
      :role,
      :email,
      :bio,
      :headshot_url,
      :tags,
      :qualifications,
      :invitation_status,
      :invitation_token_hash,
      :invitation_sent_at,
      :user_id,
      :rate_type,
      :rate_amount,
      :rate_currency
    ])
    |> validate_required([:first_name, :last_name])
    |> validate_length(:first_name, min: 1, max: 100)
    |> validate_length(:last_name, min: 1, max: 100)
    |> validate_length(:role, max: 100)
    |> validate_length(:email, max: 255)
    |> validate_length(:bio, max: 2000)
    |> validate_length(:headshot_url, max: 500)
    |> validate_tags()
    |> validate_pay_rate()
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Admin changeset satisfying Backpex's `adapter_config` contract.

  Inert since #1237: the admin dashboard denies `:edit` and toggles `active`
  through `Provider.deactivate_staff_member/1` item actions instead, so Backpex
  never calls this. It stays because `adapter_config` requires the key.
  """
  def admin_changeset(schema, attrs, _metadata) do
    cast(schema, attrs, [:active])
  end

  @doc """
  Ends a staff member's employment link.

  Deactivation is the reversible end of an employment link (`CONTEXT.md`), so it
  scrubs no PII — that is erasure's job, via `anonymize_changeset/1`. It does
  revoke an outstanding invitation for the same reason erasure does: the invite
  link is a live credential and `get_staff_member_by_token_hash/1` does not check
  `active`.
  """
  @spec deactivate_changeset(t()) :: Ecto.Changeset.t()
  def deactivate_changeset(%__MODULE__{} = staff) do
    staff
    |> change(%{active: false})
    |> revoke_invitation()
  end

  @doc """
  Reinstates a staff member's employment link.

  Deliberately narrow: a revoked invitation is not reissued (use
  `resend_staff_invitation/2`) and lead-instructor flags cleared on deactivation
  are not restored — leading a program is a deliberate promotion, not a property
  of being employed.
  """
  @spec reactivate_changeset(t()) :: Ecto.Changeset.t()
  def reactivate_changeset(%__MODULE__{} = staff), do: change(staff, %{active: true})

  @doc """
  Changeset for updating invitation-specific fields.

  Used by test fixtures to set invitation state after initial insert, and by any
  future code paths that update invitation fields independently of `edit_changeset`.
  """
  def invitation_changeset(staff_member, attrs) do
    staff_member
    |> cast(attrs, [:invitation_status, :invitation_token_hash, :invitation_sent_at, :user_id])
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Canonical GDPR tombstone for a staff member whose user erased their account.

  The name is split across both columns so `full_name/1` reads "Deleted User" and
  `initials/1` reads "DU" with no special-casing downstream.
  """
  @spec anonymized_attrs() :: map()
  def anonymized_attrs do
    %{first_name: "Deleted", last_name: "User", email: nil, bio: nil, headshot_url: nil, active: false}
  end

  @doc """
  Scrubs a staff member's PII and deactivates the row during GDPR erasure.

  Deactivating rather than deleting keeps the provider's roster history intact,
  and frees the partial unique index `staff_members_active_provider_user_index`
  (which covers only `active = true AND user_id IS NOT NULL`).
  """
  @spec anonymize_changeset(t()) :: Ecto.Changeset.t()
  def anonymize_changeset(%__MODULE__{} = staff) do
    staff
    |> change(anonymized_attrs())
    |> revoke_invitation()
  end

  # Statuses carrying an invitation that could still be redeemed.
  @outstanding_invitation_statuses [:pending, :sent]

  # An outstanding invitation is a live credential: get_staff_member_by_token_hash/1
  # (staff.ex) matches on invitation_token_hash + invitation_status == :sent and does
  # NOT check `active`, so without this the invite link would still bind a fresh user
  # account to an erased person's row.
  #
  # Deliberately bypasses @valid_invitation_transitions — erasure is an administrative
  # terminal action, not a lifecycle step, and :pending => :expired is not a legal move.
  # :accepted is left intact: already consumed, no live credential, and rewriting it
  # would falsify roster history.
  defp revoke_invitation(changeset) do
    changeset = put_change(changeset, :invitation_token_hash, nil)

    if get_field(changeset, :invitation_status) in @outstanding_invitation_statuses do
      put_change(changeset, :invitation_status, :expired)
    else
      changeset
    end
  end

  defp validate_tags(changeset) do
    case get_change(changeset, :tags) do
      nil ->
        changeset

      tags ->
        valid = Categories.categories()
        invalid = Enum.reject(tags, &(&1 in valid))

        if invalid == [] do
          changeset
        else
          add_error(changeset, :tags, "contains invalid tags: #{Enum.join(invalid, ", ")}")
        end
    end
  end

  # Validates non-negativity and all-or-none invariant, mirroring DB CHECK constraint pay_rate_all_or_none.
  defp validate_pay_rate(changeset) do
    changeset
    |> validate_number(:rate_amount, greater_than_or_equal_to: 0)
    |> validate_pay_rate_all_or_none()
    |> check_constraint(:rate_type,
      name: :pay_rate_all_or_none,
      message: "must set type, amount, and currency together"
    )
  end

  defp validate_pay_rate_all_or_none(changeset) do
    set_count = Enum.count(@pay_rate_fields, &(not is_nil(resolved_field(changeset, &1))))

    if set_count in [0, length(@pay_rate_fields)] do
      changeset
    else
      add_error(changeset, :rate_type, "must set type, amount, and currency together")
    end
  end

  defp resolved_field(changeset, field) do
    case Map.fetch(changeset.changes, field) do
      {:ok, value} -> value
      :error -> Map.get(changeset.data, field)
    end
  end

  # Normalizes a nested %PayRate{} struct or nil to flat fields so cast/2 picks them up.
  defp apply_pay_rate_struct(%{pay_rate: nil} = attrs) do
    attrs
    |> Map.delete(:pay_rate)
    |> Map.merge(%{rate_type: nil, rate_amount: nil, rate_currency: nil})
  end

  defp apply_pay_rate_struct(%{pay_rate: %PayRate{type: type, money: %Money{} = money}} = attrs) do
    attrs
    |> Map.delete(:pay_rate)
    |> Map.merge(%{rate_type: type, rate_amount: money.amount, rate_currency: money.currency})
  end

  defp apply_pay_rate_struct(attrs), do: attrs

  @doc """
  Rebuilds the virtual `:pay_rate` field from the flat `rate_*` columns.

  Called on every read path so consumers keep pattern-matching `staff.pay_rate`
  as a `%PayRate{}`. Returns the struct unchanged when no rate is set.
  """
  @spec load_pay_rate(t()) :: t()
  def load_pay_rate(%__MODULE__{} = staff), do: %{staff | pay_rate: build_pay_rate(staff)}

  defp build_pay_rate(%__MODULE__{rate_type: type, rate_amount: %Decimal{} = amount, rate_currency: currency})
       when is_atom(type) and is_atom(currency) and not is_nil(type) and not is_nil(currency) do
    with {:ok, money} <- Money.from_persistence(%{amount: amount, currency: currency}),
         {:ok, pay_rate} <- PayRate.from_persistence(%{type: type, money: money}) do
      pay_rate
    else
      _ -> nil
    end
  end

  defp build_pay_rate(_), do: nil

  # ── Query scopes ─────────────────────────────────────────────────────────

  @doc """
  Narrows a query to staff owned by `provider_id` — the tenancy guard for every
  provider-initiated read or write.

  Composing this scope makes a foreign row *unreachable* rather than fetched and
  then rejected, so the caller's `nil` branch already collapses foreign to
  missing: no existence oracle, and no ownership check left to forget.
  """
  @spec owned_by(Ecto.Queryable.t(), String.t()) :: Ecto.Query.t()
  def owned_by(query \\ __MODULE__, provider_id) when is_binary(provider_id) do
    from s in query, where: s.provider_id == ^provider_id
  end

  @doc """
  Narrows a query to staff whose employment is still live.

  Deliberately separate from `owned_by/2`: tenancy ("is this row mine?") and
  employment ("is this person still on staff?") are different questions, and the
  callers that need them differ. Composing both is right for a *new* attachment —
  assigning to a program, promoting to lead. Composing only `owned_by/2` is right
  for the employment lifecycle itself — editing, deleting, unassigning, GDPR
  erasure — all of which must still reach an offboarded member.

  Fusing the two into one getter looks like a simplification and is not: it makes
  offboarding and erasure fail to find their own targets (#1306).
  """
  @spec active(Ecto.Queryable.t()) :: Ecto.Query.t()
  def active(query \\ __MODULE__) do
    from s in query, where: s.active == true
  end

  @doc """
  Narrows a query to staff who have claimed their seat — a `User` is attached,
  so there is a real person to name.

  A third question again, separate for the same reason `active/1` is separate
  from `owned_by/2`: tenancy, employment and identity are independent. A row can
  be owned and live and still be nothing but a name a provider typed into an
  invitation nobody accepted.

  `user_id`, not `invitation_status`, is the predicate: founder self-staffing
  mints a row already linked and `:accepted` with no invitation token at all
  (ADR-0005), so keying on the status would work while keying on the token
  would silently hide every owner who teaches.

  Compose it on **public** reads only. A provider must still see the people they
  invited, so management surfaces deliberately do not narrow by this.
  """
  @spec claimed(Ecto.Queryable.t()) :: Ecto.Query.t()
  def claimed(query \\ __MODULE__) do
    from s in query, where: not is_nil(s.user_id)
  end

  # ── Functional core (ported domain validator + helpers) ──────────────────

  @doc """
  Validates the given attrs and returns `{:ok, staff}` or `{:error, [messages]}`.

  This is the domain-level validator, kept alongside the changeset so the public
  API preserves its `{:error, {:validation_error, [message]}}` contract. The
  changeset remains the persistence gatekeeper; both run on the write path.
  """
  def new(attrs) do
    attrs_with_defaults = apply_defaults(attrs)
    staff = struct(__MODULE__, attrs_with_defaults)

    case validate(staff) do
      [] -> {:ok, staff}
      errors -> {:error, errors}
    end
  end

  def valid?(%__MODULE__{} = staff), do: validate(staff) == []

  def full_name(%__MODULE__{first_name: first, last_name: last}), do: "#{first} #{last}"

  def initials(%__MODULE__{} = staff), do: NameUtils.initials_from_name(full_name(staff))

  defp apply_defaults(attrs) do
    attrs
    |> Map.put_new(:tags, [])
    |> Map.put_new(:qualifications, [])
    |> Map.put_new(:active, true)
  end

  defp validate(%__MODULE__{} = staff) do
    []
    |> validate_provider_id(staff.provider_id)
    |> validate_first_name(staff.first_name)
    |> validate_last_name(staff.last_name)
    |> validate_role(staff.role)
    |> validate_email(staff.email)
    |> validate_bio(staff.bio)
    |> validate_headshot_url(staff.headshot_url)
    |> validate_tags(staff.tags)
    |> validate_qualifications(staff.qualifications)
  end

  defp validate_provider_id(errors, id) when is_binary(id) do
    if String.trim(id) == "", do: ["Provider ID cannot be empty" | errors], else: errors
  end

  defp validate_provider_id(errors, _), do: ["Provider ID must be a string" | errors]

  defp validate_first_name(errors, name) when is_binary(name) do
    trimmed = String.trim(name)

    cond do
      trimmed == "" -> ["First name cannot be empty" | errors]
      String.length(trimmed) > 100 -> ["First name must be 100 characters or less" | errors]
      true -> errors
    end
  end

  defp validate_first_name(errors, _), do: ["First name must be a string" | errors]

  defp validate_last_name(errors, name) when is_binary(name) do
    trimmed = String.trim(name)

    cond do
      trimmed == "" -> ["Last name cannot be empty" | errors]
      String.length(trimmed) > 100 -> ["Last name must be 100 characters or less" | errors]
      true -> errors
    end
  end

  defp validate_last_name(errors, _), do: ["Last name must be a string" | errors]

  defp validate_role(errors, nil), do: errors

  defp validate_role(errors, role) when is_binary(role) do
    if String.length(role) > 100,
      do: ["Role must be 100 characters or less" | errors],
      else: errors
  end

  defp validate_role(errors, _), do: ["Role must be a string" | errors]

  defp validate_email(errors, nil), do: errors

  defp validate_email(errors, email) when is_binary(email) do
    trimmed = String.trim(email)

    cond do
      trimmed == "" -> ["Email cannot be empty if provided" | errors]
      not String.contains?(trimmed, "@") -> ["Email must contain @" | errors]
      String.length(trimmed) > 255 -> ["Email must be 255 characters or less" | errors]
      true -> errors
    end
  end

  defp validate_email(errors, _), do: ["Email must be a string" | errors]

  defp validate_bio(errors, nil), do: errors

  defp validate_bio(errors, bio) when is_binary(bio) do
    if String.length(bio) > 2000,
      do: ["Bio must be 2000 characters or less" | errors],
      else: errors
  end

  defp validate_bio(errors, _), do: ["Bio must be a string" | errors]

  defp validate_headshot_url(errors, nil), do: errors

  defp validate_headshot_url(errors, url) when is_binary(url) do
    if String.length(url) > 500,
      do: ["Headshot URL must be 500 characters or less" | errors],
      else: errors
  end

  defp validate_headshot_url(errors, _), do: ["Headshot URL must be a string" | errors]

  defp validate_tags(errors, tags) when is_list(tags) do
    valid = Categories.categories()
    invalid = Enum.reject(tags, &(&1 in valid))

    if invalid == [],
      do: errors,
      else: ["Invalid tags: #{Enum.join(invalid, ", ")}" | errors]
  end

  defp validate_tags(errors, _), do: ["Tags must be a list" | errors]

  defp validate_qualifications(errors, quals) when is_list(quals) do
    if Enum.all?(quals, &is_binary/1),
      do: errors,
      else: ["Qualifications must be a list of strings" | errors]
  end

  defp validate_qualifications(errors, _), do: ["Qualifications must be a list" | errors]

  @doc """
  Generates a URL-safe invitation token and its SHA-256 hash.
  Returns `{raw_token, token_hash}`.
  """
  @spec generate_invitation_token() :: {String.t(), binary()}
  def generate_invitation_token do
    raw_bytes = :crypto.strong_rand_bytes(32)
    raw_token = Base.url_encode64(raw_bytes, padding: false)
    token_hash = :crypto.hash(:sha256, raw_bytes)
    {raw_token, token_hash}
  end

  @doc """
  Returns the list of valid invitation status atoms.
  Derived from the state machine transitions to keep a single source of truth.
  """
  @spec valid_invitation_statuses() :: [atom()]
  def valid_invitation_statuses, do: @invitation_statuses

  @doc """
  Checks whether a staff member's invitation has expired (#{@invitation_expiry_days} days from sending).
  """
  @spec invitation_expired?(t()) :: boolean()
  def invitation_expired?(%__MODULE__{invitation_sent_at: nil}), do: false

  def invitation_expired?(%__MODULE__{invitation_sent_at: sent_at}) do
    DateTime.diff(DateTime.utc_now(), sent_at, :day) >= @invitation_expiry_days
  end

  @spec transition_invitation(t(), atom()) ::
          {:ok, t()} | {:error, :invalid_invitation_transition}
  def transition_invitation(%__MODULE__{} = staff_member, new_status) do
    allowed = Map.get(@valid_invitation_transitions, staff_member.invitation_status, [])

    if new_status in allowed do
      {:ok, %{staff_member | invitation_status: new_status}}
    else
      {:error, :invalid_invitation_transition}
    end
  end
end
