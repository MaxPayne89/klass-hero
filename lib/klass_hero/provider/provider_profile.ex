defmodule KlassHero.Provider.ProviderProfile do
  @moduledoc """
  Provider profile (`providers` table) — the aggregate root of the Provider context.

  A profile is created in `:draft` status during a deliberate staff→provider
  upgrade (ADR-0005) and completed to `:active` once business details are filled
  in. Admins verify/unverify providers; the resulting integration events
  currently have no consumers, and the catalog reads trust state through the
  Provider facade per render.

  This module is both the Ecto schema and the struct consumers pattern-match.
  Two layers guard invariants:

  - The **changesets** (`changeset/2`, `edit_changeset/2`, `completion_changeset/2`,
    `admin_changeset/3`) are the persistence-boundary gatekeepers.
  - The pure **functional core** (`new/1`, `verify/2`, `unverify/1`,
    `complete_profile/2`, predicates) enforces domain rules and returns
    string-list validation errors, preserving the frozen `{:validation_error, _}`
    contract the facade exposes.

  Providers link to the Accounts context by correlation id (`identity_id`), not a
  foreign key, preserving bounded-context independence.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  @profile_statuses [:draft, :active]
  @entity_types [:individual, :business]

  # Branding & presence (#1302). Every URL here follows the `website` rules —
  # https-only, 500 chars — so they validate as one group; `tagline` is prose.
  @social_link_fields ~w(instagram_url facebook_url tiktok_url youtube_url linkedin_url)a
  @url_branding_fields [:cover_image_url | @social_link_fields]
  @branding_fields [:tagline | @url_branding_fields]

  # The URL fields a *person* types. `cover_image_url` is deliberately absent: it
  # is set from a storage upload, so scheme-prepending it cannot repair a typo —
  # it can only launder an adapter URL past the https check that would have caught
  # it (the test stub returns `stub://…`, which became `https://stub://…`, valid
  # by inspection and wrong).
  @typed_url_fields [:website | @social_link_fields]

  @tagline_max_length 150
  @branding_url_max_length 500

  @doc "Fields a provider may set to brand their public profile (#1302)."
  @spec branding_fields() :: [atom()]
  def branding_fields, do: @branding_fields

  @doc """
  The social-link fields, in display order.

  The entity owns *which* networks exist; the web layer owns what each is
  called. Anything pairing a label with a network derives the field list from
  here rather than re-listing the atoms.
  """
  @spec social_link_fields() :: [atom()]
  def social_link_fields, do: @social_link_fields

  @doc """
  Prepends `https://` to a URL typed without a scheme.

  An explicit `http://` is passed through unchanged so it still reaches — and
  fails — the https validator. That is a deliberate insecure choice, not the
  missing-scheme typo this exists to absorb.
  """
  @spec normalize_url(String.t() | nil) :: String.t() | nil
  def normalize_url(nil), do: nil

  def normalize_url(url) when is_binary(url) do
    case String.trim(url) do
      "" -> nil
      trimmed -> ensure_scheme(trimmed)
    end
  end

  def normalize_url(url), do: url

  defp ensure_scheme("https://" <> _ = url), do: url
  defp ensure_scheme("http://" <> _ = url), do: url
  defp ensure_scheme(url), do: "https://" <> url

  schema "providers" do
    field :identity_id, :binary_id
    field :entity_type, Ecto.Enum, values: @entity_types, default: :individual
    field :business_name, :string
    field :business_owner_email, :string
    field :responsible_person_name, :string
    field :responsible_person_role, :string
    field :legal_business_name, :string
    field :registration_number, :string
    field :registration_country, :string
    field :description, :string
    field :phone, :string
    field :website, :string
    field :address, :string
    field :logo_url, :string
    field :verified, :boolean, default: false
    field :verified_at, :utc_datetime
    field :categories, {:array, :string}, default: []
    field :profile_status, Ecto.Enum, values: @profile_statuses, default: :active

    # Branding & presence, shown on the public profile page (#1302). All optional.
    field :tagline, :string
    field :cover_image_url, :string
    field :instagram_url, :string
    field :facebook_url, :string
    field :tiktok_url, :string
    field :youtube_url, :string
    field :linkedin_url, :string

    # Accounts owns the verifier; correlation id only, no association (#1434).
    field :verified_by_id, :binary_id

    timestamps()
  end

  @type t :: %__MODULE__{}

  @doc "Returns the list of valid profile statuses."
  @spec valid_profile_statuses() :: [:draft | :active]
  def valid_profile_statuses, do: @profile_statuses

  # ── Changesets (persistence-boundary gatekeepers) ──────────────────────────

  @doc "Changeset for insert/update of a provider profile."
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [
      :identity_id,
      :entity_type,
      :business_name,
      :business_owner_email,
      :description,
      :phone,
      :website,
      :address,
      :logo_url,
      :verified,
      :verified_at,
      :verified_by_id,
      :categories,
      :profile_status
      | @branding_fields
    ])
    |> validate_required([:identity_id, :business_name])
    |> validate_profile_fields()
    |> validate_length(:logo_url, min: 1, max: 500)
    |> unique_constraint(:identity_id,
      name: :providers_identity_id_index,
      message: "Provider profile already exists for this identity"
    )
  end

  @doc """
  Form changeset for provider profile editing via LiveView.

  Casts `:description` plus the branding fields (#1302). logo_url and
  cover_image_url are set programmatically after upload; other fields
  (business_name, phone, etc.) are not editable in this form.
  """
  def edit_changeset(schema, attrs) do
    schema
    |> cast(attrs, [:description | @branding_fields])
    |> validate_length(:description, max: 1000)
    |> validate_branding_fields()
  end

  @doc """
  Form changeset for provider profile completion by staff-invite providers.

  Casts all fields a provider needs to fill during profile completion:
  business_name, description, phone, website, address, categories.
  Logo URL is set programmatically after upload (not in this changeset).
  """
  @completion_cast_fields ~w(business_name description phone website address categories entity_type)a ++
                            @branding_fields

  def completion_changeset(schema, attrs) do
    schema
    |> cast(attrs, @completion_cast_fields)
    |> validate_required([:business_name, :description])
    |> validate_profile_fields()
  end

  @doc """
  Admin changeset for provider profile management via Backpex.

  Casts `verified` — provider-owned fields
  (business_name, description, phone, etc.) are excluded.

  When `verified` changes, also sets `verified_at` and `verified_by_id`
  to maintain consistency with the domain model's verify/unverify behaviour.

  Accepts 3 args to match the Backpex changeset callback signature.
  The metadata keyword list includes `:assigns` with the current admin scope.
  """
  def admin_changeset(schema, attrs, metadata) do
    schema
    |> cast(attrs, [:verified])
    |> maybe_set_verification_fields(metadata)
  end

  # Keeps verified_at and verified_by_id in sync with verified flag (audit trail).
  defp maybe_set_verification_fields(changeset, metadata) do
    case get_change(changeset, :verified) do
      true ->
        admin_id = metadata[:assigns].current_scope.user.id

        changeset
        |> put_change(:verified_at, DateTime.utc_now() |> DateTime.truncate(:second))
        |> put_change(:verified_by_id, admin_id)

      false ->
        changeset
        |> put_change(:verified_at, nil)
        |> put_change(:verified_by_id, nil)

      nil ->
        changeset
    end
  end

  defp validate_profile_fields(changeset) do
    changeset
    |> validate_length(:business_name, min: 1, max: 200)
    |> validate_length(:description, min: 1, max: 1000)
    |> validate_length(:phone, min: 1, max: 20)
    |> validate_length(:website, min: 1, max: 500)
    |> validate_website_protocol()
    |> validate_length(:address, min: 1, max: 500)
    |> validate_branding_fields()
  end

  defp validate_branding_fields(changeset) do
    changeset = validate_length(changeset, :tagline, max: @tagline_max_length)

    changeset =
      Enum.reduce(@social_link_fields, changeset, fn field, acc ->
        update_change(acc, field, &normalize_url/1)
      end)

    Enum.reduce(@url_branding_fields, changeset, fn field, acc ->
      acc
      |> validate_length(field, max: @branding_url_max_length)
      |> validate_https_url(field)
    end)
  end

  defp validate_https_url(changeset, field) do
    case get_change(changeset, field) do
      url when is_binary(url) ->
        if String.starts_with?(url, "https://") do
          changeset
        else
          add_error(changeset, field, "must start with https://")
        end

      _ ->
        changeset
    end
  end

  defp validate_website_protocol(changeset) do
    changeset = update_change(changeset, :website, &normalize_url/1)

    case get_change(changeset, :website) do
      website when is_binary(website) ->
        if String.starts_with?(website, "https://") do
          changeset
        else
          add_error(changeset, :website, "must start with https://")
        end

      _ ->
        changeset
    end
  end

  @doc """
  Narrow changeset for the Responsible Person (ADR-0010) — the ONLY path that may
  write `responsible_person_name`/`responsible_person_role`.

  These two fields are deliberately absent from every other changeset and from the
  `@profile_persist_fields`/`@completion_fields` whitelists, so the dedicated
  `set_responsible_person` command is their sole mutator. Values are normalized
  (trimmed, internal whitespace collapsed) so a stray space never reads as a change.
  """
  @responsible_person_fields ~w(responsible_person_name responsible_person_role)a

  def responsible_person_changeset(schema, attrs) do
    schema
    |> cast(attrs, @responsible_person_fields)
    |> update_change(:responsible_person_name, &normalize_field/1)
    |> update_change(:responsible_person_role, &normalize_field/1)
    |> validate_required(@responsible_person_fields)
  end

  @doc """
  Narrow changeset for business registration (B2, issue #956) — the ONLY path that may
  write `legal_business_name`/`registration_number`/`registration_country`.

  Like the responsible-person fields, these are deliberately absent from every other
  changeset and whitelist, so the `submit_business_registration` command is their sole
  mutator. `registration_country` is a curated string (`"DE" | "GB" | "OTHER"`, ADR-0011);
  the legal name and number are trimmed. Unlike B1, a registration change carries no
  `requires` edge and never resets vetting (ADR-0010).
  """
  @business_registration_fields ~w(legal_business_name registration_number registration_country)a
  @registration_countries ~w(DE GB OTHER)

  def business_registration_changeset(schema, attrs) do
    schema
    |> cast(attrs, @business_registration_fields)
    |> update_change(:legal_business_name, &normalize_field/1)
    |> update_change(:registration_number, &normalize_field/1)
    |> validate_required(@business_registration_fields)
    |> validate_inclusion(:registration_country, @registration_countries)
  end

  @doc "The curated set of registration-country codes B2 accepts."
  @spec registration_countries() :: [String.t()]
  def registration_countries, do: @registration_countries

  # ── Functional core (pure domain rules) ────────────────────────────────────

  @doc """
  Classifies a submitted `(name, role)` against the stored Responsible Person by
  normalized exact match (ADR-0010). Pure — no persistence.

  - both stored fields blank → `:set` (first capture)
  - normalized-equal to stored → `:unchanged` (the typo-guard: a trailing/double
    space must not nuke a passed identity check)
  - otherwise → `:changed` (resets identity + cascades, per the command)
  """
  @spec responsible_person_change(t(), String.t() | nil, String.t() | nil) ::
          :unchanged | :set | :changed
  def responsible_person_change(%__MODULE__{} = profile, name, role) do
    stored_name = normalize_field(profile.responsible_person_name)
    stored_role = normalize_field(profile.responsible_person_role)
    stored = {stored_name, stored_role}
    submitted = {normalize_field(name), normalize_field(role)}

    cond do
      stored == {"", ""} -> :set
      stored == submitted -> :unchanged
      true -> :changed
    end
  end

  @doc """
  Whether this profile has a Responsible Person on record — the domain precondition for starting a
  business's Stripe Identity session (ADR-0010: "name capture is mandatory before identity"). Pure,
  normalized (whitespace-only counts as blank). Consumed by
  `Vetting.create_identity_verification_session/2`'s business gate.
  """
  @spec responsible_person_captured?(t()) :: boolean()
  def responsible_person_captured?(%__MODULE__{} = profile) do
    normalize_field(profile.responsible_person_name) != "" and
      normalize_field(profile.responsible_person_role) != ""
  end

  @doc """
  The natural person who signs an agreement on this profile's behalf. For a `:business`, the named
  responsible person (legally accountable), or `nil` when none is on record; for an individual,
  `nil` — they sign as themselves. Blank/whitespace-only names normalize to `nil` so callers can
  treat "no signer on record" uniformly (the write path fails closed, the read path shows nothing).

  Single source of truth for the "who signs" rule, consumed by both `SubmitSignedAgreement`
  (enforcement) and the verification LiveView (display).
  """
  @spec agreement_signer_name(t()) :: String.t() | nil
  def agreement_signer_name(%__MODULE__{entity_type: :business, responsible_person_name: name}) do
    if normalize_field(name) != "", do: name
  end

  def agreement_signer_name(%__MODULE__{}), do: nil

  # Trims ends and collapses internal whitespace runs to a single space. nil → "".
  defp normalize_field(nil), do: ""

  defp normalize_field(value) when is_binary(value) do
    value |> String.trim() |> String.replace(~r/\s+/, " ")
  end

  @doc """
  Builds and validates a provider profile struct from attrs.

  Returns `{:ok, t()}` or `{:error, [message]}` — the string-list error the
  facade wraps into `{:error, {:validation_error, errors}}`.
  """
  @spec new(map()) :: {:ok, t()} | {:error, [String.t()]}
  def new(attrs) do
    profile = __MODULE__ |> struct!(apply_defaults(attrs)) |> normalize_urls()

    case validate(profile) do
      [] -> {:ok, profile}
      errors -> {:error, errors}
    end
  end

  # The changesets normalize per-field via `update_change`; the pure core builds a
  # whole struct, so it normalizes the same fields on the struct instead. Both
  # builders below do this identically — what differs is the caller:
  # `update_provider_profile/2` discards `new/1`'s struct and persists the
  # changeset's, while `complete_provider_profile/2` persists this one.
  defp normalize_urls(%__MODULE__{} = profile) do
    Enum.reduce(@typed_url_fields, profile, fn field, acc ->
      Map.update!(acc, field, &normalize_url/1)
    end)
  end

  defp apply_defaults(attrs) do
    attrs
    |> Map.put_new(:verified, false)
    |> Map.put_new(:categories, [])
    |> Map.put_new(:profile_status, :active)
  end

  @doc "Returns true when the profile passes all domain validations."
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{} = profile), do: validate(profile) == []

  @doc "Checks if the provider has been verified."
  @spec verified?(t()) :: boolean()
  def verified?(%__MODULE__{verified: true}), do: true
  def verified?(_), do: false

  @doc "Returns true if the profile is in draft status (needs completion)."
  @spec draft?(t()) :: boolean()
  def draft?(%__MODULE__{profile_status: :draft}), do: true
  def draft?(_), do: false

  @doc """
  Marks a provider profile as verified by an admin.

  Records the admin who performed the verification and the timestamp.
  Idempotent — verifying an already-verified provider updates the audit trail.
  """
  @spec verify(t(), String.t() | nil) :: {:ok, t()}
  def verify(%__MODULE__{} = profile, admin_id) when is_binary(admin_id) or is_nil(admin_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, %{profile | verified: true, verified_at: now, verified_by_id: admin_id, updated_at: now}}
  end

  @doc """
  Revokes verification from a provider profile.

  Clears the verified flag, timestamp, and admin audit trail.
  Idempotent — unverifying an already-unverified provider succeeds.
  """
  @spec unverify(t()) :: {:ok, t()}
  def unverify(%__MODULE__{} = profile) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    {:ok, %{profile | verified: false, verified_at: nil, verified_by_id: nil, updated_at: now}}
  end

  @doc """
  Completes a draft provider profile with the given fields.

  Only allowed when profile_status is :draft. Sets status to :active.

  Returns:
  - `{:ok, t()}` on success
  - `{:error, :already_active}` if profile_status is not :draft
  - `{:error, [message]}` if validation fails
  """
  @completion_fields ~w(business_name description phone website address logo_url categories entity_type)a ++
                       @branding_fields

  @spec complete_profile(t(), map()) :: {:ok, t()} | {:error, :already_active | [String.t()]}
  def complete_profile(%__MODULE__{profile_status: :draft} = profile, attrs) when is_map(attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    updated =
      profile
      |> struct(Map.take(attrs, @completion_fields))
      |> normalize_urls()
      |> Map.put(:profile_status, :active)
      |> Map.put(:updated_at, now)

    case validate(updated) do
      [] -> {:ok, updated}
      errors -> {:error, errors}
    end
  end

  def complete_profile(%__MODULE__{profile_status: :active}, _attrs), do: {:error, :already_active}

  # ── Pure validation pipeline (drives new/1 and complete_profile/2) ──────────

  defp validate(%__MODULE__{} = profile) do
    []
    |> validate_identity_id(profile.identity_id)
    |> validate_business_name(profile.business_name)
    |> validate_description(profile.description)
    |> validate_phone(profile.phone)
    |> validate_website(profile.website)
    |> validate_address(profile.address)
    |> validate_logo_url(profile.logo_url)
    |> validate_verified(profile.verified)
    |> validate_verified_at(profile.verified_at)
    |> validate_categories(profile.categories)
    |> validate_profile_status(profile.profile_status)
    |> validate_entity_type(profile.entity_type)
    |> validate_business_owner_email(profile.business_owner_email)
    |> validate_tagline(profile.tagline)
    |> validate_branding_urls(profile)
  end

  defp validate_tagline(errors, nil), do: errors

  defp validate_tagline(errors, tagline) when is_binary(tagline) do
    if String.length(tagline) > @tagline_max_length do
      ["Tagline must be #{@tagline_max_length} characters or less" | errors]
    else
      errors
    end
  end

  defp validate_tagline(errors, _), do: ["Tagline must be a string" | errors]

  defp validate_branding_urls(errors, profile) do
    Enum.reduce(@url_branding_fields, errors, fn field, acc ->
      validate_branding_url(acc, label_for(field), Map.fetch!(profile, field))
    end)
  end

  defp validate_branding_url(errors, _label, nil), do: errors

  # A blank value means "not set", never "invalid". These are optional fields, and
  # `validate/1` re-validates the WHOLE struct on every update — so rejecting ""
  # would mean a single blank column, however it got there (a backfill, an import,
  # raw SQL), permanently blocks every later edit of that provider, including edits
  # to unrelated fields. Ecto's cast already collapses "" to nil on the changeset
  # side; this keeps the pure path idempotent in the same way.
  defp validate_branding_url(errors, label, url) when is_binary(url) do
    trimmed = String.trim(url)

    cond do
      trimmed == "" -> errors
      not String.starts_with?(trimmed, "https://") -> ["#{label} must start with https://" | errors]
      String.length(trimmed) > @branding_url_max_length -> ["#{label} must be 500 characters or less" | errors]
      true -> errors
    end
  end

  defp validate_branding_url(errors, label, _), do: ["#{label} must be a string" | errors]

  defp label_for(:cover_image_url), do: "Cover image URL"
  defp label_for(:instagram_url), do: "Instagram URL"
  defp label_for(:facebook_url), do: "Facebook URL"
  defp label_for(:tiktok_url), do: "TikTok URL"
  defp label_for(:youtube_url), do: "YouTube URL"
  defp label_for(:linkedin_url), do: "LinkedIn URL"

  defp validate_business_owner_email(errors, nil), do: errors

  defp validate_business_owner_email(errors, email) when is_binary(email) do
    if String.length(email) > 254 do
      ["Business owner email must be 254 characters or less" | errors]
    else
      errors
    end
  end

  defp validate_business_owner_email(errors, _), do: ["Business owner email must be a string" | errors]

  defp validate_identity_id(errors, identity_id) when is_binary(identity_id) do
    if String.trim(identity_id) == "" do
      ["Identity ID cannot be empty" | errors]
    else
      errors
    end
  end

  defp validate_identity_id(errors, _), do: ["Identity ID must be a string" | errors]

  defp validate_business_name(errors, business_name) when is_binary(business_name) do
    trimmed = String.trim(business_name)

    cond do
      trimmed == "" -> ["Business name cannot be empty" | errors]
      String.length(trimmed) > 200 -> ["Business name must be 200 characters or less" | errors]
      true -> errors
    end
  end

  defp validate_business_name(errors, _), do: ["Business name must be a string" | errors]

  defp validate_description(errors, nil), do: errors

  defp validate_description(errors, description) when is_binary(description) do
    trimmed = String.trim(description)

    cond do
      trimmed == "" -> ["Description cannot be empty if provided" | errors]
      String.length(trimmed) > 1000 -> ["Description must be 1000 characters or less" | errors]
      true -> errors
    end
  end

  defp validate_description(errors, _), do: ["Description must be a string" | errors]

  defp validate_phone(errors, nil), do: errors

  defp validate_phone(errors, phone) when is_binary(phone) do
    trimmed = String.trim(phone)

    cond do
      trimmed == "" -> ["Phone cannot be empty if provided" | errors]
      String.length(trimmed) > 20 -> ["Phone must be 20 characters or less" | errors]
      true -> errors
    end
  end

  defp validate_phone(errors, _), do: ["Phone must be a string" | errors]

  defp validate_website(errors, nil), do: errors

  defp validate_website(errors, website) when is_binary(website) do
    trimmed = String.trim(website)

    cond do
      trimmed == "" ->
        ["Website cannot be empty if provided" | errors]

      not String.starts_with?(trimmed, "https://") ->
        ["Website must start with https://" | errors]

      String.length(trimmed) > 500 ->
        ["Website must be 500 characters or less" | errors]

      true ->
        errors
    end
  end

  defp validate_website(errors, _), do: ["Website must be a string" | errors]

  defp validate_address(errors, nil), do: errors

  defp validate_address(errors, address) when is_binary(address) do
    trimmed = String.trim(address)

    cond do
      trimmed == "" -> ["Address cannot be empty if provided" | errors]
      String.length(trimmed) > 500 -> ["Address must be 500 characters or less" | errors]
      true -> errors
    end
  end

  defp validate_address(errors, _), do: ["Address must be a string" | errors]

  defp validate_logo_url(errors, nil), do: errors

  defp validate_logo_url(errors, logo_url) when is_binary(logo_url) do
    trimmed = String.trim(logo_url)

    cond do
      trimmed == "" -> ["Logo URL cannot be empty if provided" | errors]
      String.length(trimmed) > 500 -> ["Logo URL must be 500 characters or less" | errors]
      true -> errors
    end
  end

  defp validate_logo_url(errors, _), do: ["Logo URL must be a string" | errors]

  defp validate_verified(errors, nil), do: errors
  defp validate_verified(errors, verified) when is_boolean(verified), do: errors
  defp validate_verified(errors, _), do: ["Verified must be a boolean" | errors]

  defp validate_verified_at(errors, nil), do: errors
  defp validate_verified_at(errors, %DateTime{}), do: errors
  defp validate_verified_at(errors, _), do: ["Verified at must be a DateTime" | errors]

  defp validate_categories(errors, nil), do: errors

  defp validate_categories(errors, categories) when is_list(categories) do
    if Enum.all?(categories, &is_binary/1) do
      errors
    else
      ["Categories must be a list of strings" | errors]
    end
  end

  defp validate_categories(errors, _), do: ["Categories must be a list" | errors]

  defp validate_profile_status(errors, status) when status in @profile_statuses, do: errors
  defp validate_profile_status(errors, _), do: ["profile_status must be :draft or :active" | errors]

  defp validate_entity_type(errors, entity_type) when entity_type in @entity_types, do: errors
  defp validate_entity_type(errors, _), do: ["entity_type must be :individual or :business" | errors]
end
