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
  import Ecto.Query, only: [from: 2]

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
    field :is_lead_instructor, :boolean, default: false

    timestamps()
  end

  @type t :: %__MODULE__{}

  @castable_fields ~w(program_id assigned_at)a
  @optional_fields ~w(unassigned_at is_lead_instructor)a

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

  @doc """
  Changeset toggling the lead-instructor flag on an existing assignment.

  Carries the partial unique constraint so promoting a second staff member to
  lead before the previous lead is cleared surfaces as a changeset error rather
  than a raw DB exception.
  """
  def lead_changeset(schema, is_lead?) when is_boolean(is_lead?) do
    schema
    |> change(%{is_lead_instructor: is_lead?})
    |> unique_constraint(:program_id,
      name: :program_staff_assignments_single_lead,
      message: "program already has a lead instructor"
    )
  end

  @doc """
  Narrows a query to assignments owned by `provider_id`.

  Composed into every mutation query so a crafted `program_id`/`staff_member_id`
  pair cannot reach another provider's row — the guard holds even where a
  caller's pre-check is missing.
  """
  @spec owned_by(Ecto.Queryable.t(), String.t()) :: Ecto.Query.t()
  def owned_by(query \\ __MODULE__, provider_id) when is_binary(provider_id) do
    from a in query, where: a.provider_id == ^provider_id
  end

  @doc "Returns true when the assignment is still active (never unassigned)."
  @spec active?(t()) :: boolean()
  def active?(%__MODULE__{unassigned_at: nil}), do: true
  def active?(%__MODULE__{}), do: false

  @doc "Returns true when the assignment is the program's active lead instructor."
  @spec lead?(t()) :: boolean()
  def lead?(%__MODULE__{is_lead_instructor: true, unassigned_at: nil}), do: true
  def lead?(%__MODULE__{}), do: false
end
