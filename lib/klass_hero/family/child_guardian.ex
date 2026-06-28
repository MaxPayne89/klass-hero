defmodule KlassHero.Family.ChildGuardian do
  @moduledoc """
  The `children_guardians` join table linking children to their guardians
  (parents, legal guardians, etc.) in a many-to-many relationship. Each link
  records the relationship type and whether this guardian is the primary contact.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  @valid_relationships ~w(parent guardian other)

  schema "children_guardians" do
    field :child_id, :binary_id
    field :guardian_id, :binary_id
    field :relationship, :string, default: "parent"
    field :is_primary, :boolean, default: false

    timestamps()
  end

  def changeset(schema \\ %__MODULE__{}, attrs) do
    schema
    |> cast(attrs, [:child_id, :guardian_id, :relationship, :is_primary])
    |> validate_required([:child_id, :guardian_id])
    |> validate_inclusion(:relationship, @valid_relationships)
    |> unique_constraint([:child_id, :guardian_id],
      name: :children_guardians_child_id_guardian_id_index
    )
    |> unique_constraint(:child_id,
      name: :children_guardians_one_primary_per_child,
      message: "child already has a primary guardian"
    )
    |> check_constraint(:relationship, name: :valid_relationship)
    |> foreign_key_constraint(:child_id)
    |> foreign_key_constraint(:guardian_id)
  end

  def valid_relationships, do: @valid_relationships
end
