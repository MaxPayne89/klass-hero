defmodule KlassHero.Provider.Adapters.Driven.Persistence.Schemas.StaffMemberSchema do
  @moduledoc """
  Ecto schema for the staff_members table.

  Use StaffMemberMapper to convert between this schema and domain StaffMember entities.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.ProviderProfileSchema
  alias KlassHero.Provider.Domain.Models.{PayRate, StaffMember}
  alias KlassHero.Shared.Categories
  alias KlassHero.Shared.Domain.Types.Money

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "staff_members" do
    belongs_to :provider, ProviderProfileSchema, type: :binary_id
    field :first_name, :string
    field :last_name, :string
    field :role, :string
    field :email, :string
    field :bio, :string
    field :headshot_url, :string
    field :tags, {:array, :string}, default: []
    field :qualifications, {:array, :string}, default: []
    field :active, :boolean, default: true
    field :invitation_status, :string
    field :invitation_token_hash, :binary
    field :invitation_sent_at, :utc_datetime_usec
    field :user_id, :binary_id
    field :rate_type, Ecto.Enum, values: PayRate.valid_types()
    field :rate_amount, :decimal
    field :rate_currency, Ecto.Enum, values: Money.valid_currencies()

    timestamps()
  end

  @pay_rate_fields [:rate_type, :rate_amount, :rate_currency]

  @doc """
  Changeset for creating a new staff member.

  provider_id and user_id are set programmatically via put_change, not cast
  from user input. user_id is only present for self-staffing (#969), where the
  row is born already linked.

  Validation constants intentionally mirror StaffMember domain model.
  Domain validates on write; Ecto validates at persistence boundary.
  Keep both in sync when changing constraints.
  """
  def create_changeset(schema, attrs) do
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
    |> validate_inclusion(
      :invitation_status,
      Enum.map(StaffMember.valid_invitation_statuses(), &to_string/1)
    )
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
  Excludes provider_id (set programmatically, immutable after creation).

  Validation constants intentionally mirror StaffMember domain model.
  Domain validates on write; Ecto validates at persistence boundary.
  Keep both in sync when changing constraints.
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
      :active,
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
    |> validate_inclusion(
      :invitation_status,
      Enum.map(StaffMember.valid_invitation_statuses(), &to_string/1)
    )
    |> validate_pay_rate()
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Admin changeset for Backpex dashboard edits.

  Only allows toggling `active` status — all other fields are provider-owned.
  Accepts Backpex 3-arg signature (schema, attrs, metadata); metadata is unused
  since no audit trail fields are needed for active toggle.
  """
  def admin_changeset(schema, attrs, _metadata) do
    cast(schema, attrs, [:active])
  end

  @doc """
  Changeset for updating invitation-specific fields.

  Used by test fixtures to set invitation state after initial insert, and by
  any future code paths that need to update invitation fields independently
  of the general `edit_changeset`.
  """
  def invitation_changeset(staff_member, attrs) do
    staff_member
    |> cast(attrs, [:invitation_status, :invitation_token_hash, :invitation_sent_at, :user_id])
    |> validate_inclusion(
      :invitation_status,
      Enum.map(StaffMember.valid_invitation_statuses(), &to_string/1)
    )
    |> foreign_key_constraint(:user_id)
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

  # rate_type and rate_currency use Ecto.Enum (value inclusion handled at cast).
  # This validates non-negativity and enforces the all-or-none invariant —
  # mirrors the DB CHECK constraint pay_rate_all_or_none.
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

  # Callers may hand us a `%PayRate{}` via a `:pay_rate` key (e.g. use-case flow)
  # or the three flat fields directly (e.g. a LiveView form). Normalize to flat
  # so `cast/2` picks them up.
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
end
