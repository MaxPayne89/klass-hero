defmodule KlassHero.Provider.SessionStaffAssignment do
  @moduledoc """
  Schema-as-struct for the `session_staff_assignments` table — a **sparse override**
  of a program's staffing for one session.

  Rows exist only where a provider deliberately overrode the session: a substitute
  covering one day, or two staff splitting a weekly schedule. A session with no
  active rows here inherits the program roster, so the common case costs nothing
  and there is no snapshot to drift.

  That sparseness is the whole design. The alternative — copying
  `program_staff_assignments` into every session at creation — was rejected because
  it rebuilds the denormalised staffing mirror #1321 deleted, at up to 500 sessions
  × N staff per program, with no way to correct the copy when program staffing
  later changes.

  `KlassHero.Provider.Assignments.get_session_staffing/1` is the only thing that
  resolves override-vs-program; nothing else re-derives the rule.

  ## Constraints

  A staff member can hold one active override per session (partial unique index on
  `session_id + staff_member_id` where `unassigned_at IS NULL`), and a session can
  have one active lead (`session_staff_assignments_single_lead`). Soft-deleting via
  `unassigned_at` lifts both and allows re-assignment.
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  alias KlassHero.Provider.ProviderProfile
  alias KlassHero.Provider.StaffMember

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "session_staff_assignments" do
    belongs_to :provider, ProviderProfile
    belongs_to :staff_member, StaffMember
    field :session_id, :binary_id
    field :assigned_by_user_id, :binary_id
    field :assigned_at, :utc_datetime_usec
    field :unassigned_at, :utc_datetime_usec
    field :is_lead_instructor, :boolean, default: false

    timestamps()
  end

  @type t :: %__MODULE__{}

  @castable_fields ~w(session_id assigned_at)a
  @optional_fields ~w(unassigned_at is_lead_instructor assigned_by_user_id)a

  @doc """
  Changeset for creating a session staff override.

  `provider_id` and `staff_member_id` are set programmatically, not cast from user
  input — the command takes them from the ownership-proven `StaffMember`, which is
  the only tenancy authority an INSERT can carry (a query scope cannot reach it).
  """
  def create_changeset(schema \\ %__MODULE__{}, attrs) do
    schema
    |> cast(attrs, @castable_fields ++ @optional_fields)
    |> put_change(:provider_id, attrs[:provider_id] || attrs["provider_id"])
    |> put_change(:staff_member_id, attrs[:staff_member_id] || attrs["staff_member_id"])
    |> validate_required([:provider_id, :session_id, :staff_member_id, :assigned_at])
    |> foreign_key_constraint(:provider_id)
    |> foreign_key_constraint(:session_id)
    |> foreign_key_constraint(:staff_member_id)
    |> unique_constraint([:session_id, :staff_member_id],
      name: :session_staff_assignments_active_unique,
      message: "staff member is already assigned to this session"
    )
    |> unique_constraint(:session_id,
      name: :session_staff_assignments_single_lead,
      message: "session already has a lead instructor"
    )
  end

  @doc """
  Changeset retiring an override, which lifts both partial unique indexes.

  Clears `is_lead_instructor` for the same reason the program-level sibling does:
  a retired row that still reads as leading is exactly the state a later query
  forgetting `is_nil(unassigned_at)` would silently believe.
  """
  def unassign_changeset(schema) do
    change(schema, %{
      unassigned_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
      is_lead_instructor: false
    })
  end

  @doc """
  Changeset toggling the lead flag on an existing override.

  Carries the single-lead partial unique constraint so promoting a second lead
  before the previous one is cleared surfaces as a changeset error rather than a
  raw DB exception.
  """
  def lead_changeset(schema, is_lead?) when is_boolean(is_lead?) do
    schema
    |> change(%{is_lead_instructor: is_lead?})
    |> unique_constraint(:session_id,
      name: :session_staff_assignments_single_lead,
      message: "session already has a lead instructor"
    )
  end

  @doc """
  Narrows a query to overrides owned by `provider_id`.

  Composed into every mutation query so a crafted `session_id`/`staff_member_id`
  pair cannot reach another provider's row, even where a caller's pre-check is
  missing.
  """
  @spec owned_by(Ecto.Queryable.t(), String.t()) :: Ecto.Query.t()
  def owned_by(query \\ __MODULE__, provider_id) when is_binary(provider_id) do
    from a in query, where: a.provider_id == ^provider_id
  end

  @doc "Returns true when the override is still active (never retired)."
  @spec active?(t()) :: boolean()
  def active?(%__MODULE__{unassigned_at: nil}), do: true
  def active?(%__MODULE__{}), do: false

  @doc "Returns true when the override is the session's active lead instructor."
  @spec lead?(t()) :: boolean()
  def lead?(%__MODULE__{is_lead_instructor: true, unassigned_at: nil}), do: true
  def lead?(%__MODULE__{}), do: false
end
