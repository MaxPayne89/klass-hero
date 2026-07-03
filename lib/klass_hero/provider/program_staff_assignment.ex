defmodule KlassHero.Provider.ProgramStaffAssignment do
  @moduledoc """
  Schema-as-struct for the `program_staff_assignments` table.

  Tracks which staff members are assigned to which programs for a provider.
  A staff member can only have one active assignment per program, enforced via
  a partial unique index on `program_id + staff_member_id` where
  `unassigned_at IS NULL`. Soft-deleting (setting `unassigned_at`) lifts that
  constraint and allows future re-assignment.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.Provider.ProviderProfile
  alias KlassHero.Provider.StaffMember

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "program_staff_assignments" do
    belongs_to :provider, ProviderProfile
    belongs_to :staff_member, StaffMember
    field :program_id, :binary_id
    field :assigned_at, :utc_datetime_usec
    field :unassigned_at, :utc_datetime_usec

    timestamps()
  end

  @type t :: %__MODULE__{}

  @castable_fields ~w(program_id assigned_at)a
  @optional_fields ~w(unassigned_at)a

  @doc """
  Changeset for creating a new program staff assignment.

  `provider_id` and `staff_member_id` are set programmatically, not cast from
  user input. `assigned_at` must be supplied by the caller (`DateTime.utc_now/0`).
  """
  def create_changeset(schema \\ %__MODULE__{}, attrs) do
    schema
    |> cast(attrs, @castable_fields ++ @optional_fields)
    |> put_change(:provider_id, attrs[:provider_id] || attrs["provider_id"])
    |> put_change(:staff_member_id, attrs[:staff_member_id] || attrs["staff_member_id"])
    |> validate_required([:provider_id, :program_id, :staff_member_id, :assigned_at])
    |> foreign_key_constraint(:provider_id)
    |> foreign_key_constraint(:program_id)
    |> foreign_key_constraint(:staff_member_id)
    |> unique_constraint([:program_id, :staff_member_id],
      name: :program_staff_assignments_active_unique,
      message: "staff member is already assigned to this program"
    )
  end

  @doc """
  Changeset for unassigning a staff member from a program.

  Sets `unassigned_at` to the current UTC time, which lifts the partial unique
  index constraint and allows future re-assignment.
  """
  def unassign_changeset(schema) do
    change(schema, %{unassigned_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)})
  end

  @doc "Returns true when the assignment is still active (never unassigned)."
  @spec active?(t()) :: boolean()
  def active?(%__MODULE__{unassigned_at: nil}), do: true
  def active?(%__MODULE__{}), do: false
end
