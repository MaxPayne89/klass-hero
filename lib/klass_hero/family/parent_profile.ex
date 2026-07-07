defmodule KlassHero.Family.ParentProfile do
  @moduledoc """
  A parent profile in the Family context — the link between an Accounts identity
  and family data.

  The Ecto schema is the domain struct: validation lives in the changeset.
  Parents reference the Accounts context by correlation id (`identity_id`),
  not a foreign key.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "parents" do
    field :identity_id, :binary_id
    field :display_name, :string
    field :phone, :string
    field :location, :string
    field :notification_preferences, :map

    timestamps()
  end

  @doc """
  Changeset for creating/updating a parent profile.

  - Required: `identity_id`
  - `display_name` 1–100, `phone` 1–20, `location` 1–200 characters when present
  - `identity_id` is unique (one profile per identity)
  """
  def changeset(parent_profile, attrs) do
    parent_profile
    |> cast(attrs, [
      :identity_id,
      :display_name,
      :phone,
      :location,
      :notification_preferences
    ])
    |> validate_required([:identity_id])
    |> validate_length(:display_name, min: 1, max: 100)
    |> validate_length(:phone, min: 1, max: 20)
    |> validate_length(:location, min: 1, max: 200)
    |> unique_constraint(:identity_id,
      name: :parents_identity_id_index,
      message: "Parent profile already exists for this identity"
    )
  end

  @doc "Whether the profile has any notification preferences configured."
  def has_notification_preferences?(%__MODULE__{notification_preferences: prefs})
      when is_map(prefs) and map_size(prefs) > 0, do: true

  def has_notification_preferences?(%__MODULE__{}), do: false

  @type t :: %__MODULE__{
          id: binary() | nil,
          identity_id: binary() | nil,
          display_name: String.t() | nil,
          phone: String.t() | nil,
          location: String.t() | nil,
          notification_preferences: map() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }
end
