defmodule KlassHero.Enrollment.EnrollmentPolicy do
  @moduledoc """
  Enrollment capacity policy for a program (`enrollment_policies` table).

  Owned by the Enrollment context. Providers configure min/max enrollment when
  creating programs; the context enforces these limits.

  This module is both the Ecto schema and the struct consumers pattern-match.
  The changeset is the single validation gatekeeper; the pure functions
  (`has_capacity?/2`, `meets_minimum?/2`, `remaining_capacity/2`) are the
  functional core for capacity math.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "enrollment_policies" do
    field :program_id, :binary_id
    field :min_enrollment, :integer
    field :max_enrollment, :integer

    timestamps()
  end

  @type t :: %__MODULE__{}

  @required_fields ~w(program_id)a
  @optional_fields ~w(min_enrollment max_enrollment)a

  @doc """
  Changeset for enrollment policy creation or update.

  Both `min_enrollment` and `max_enrollment` are optional positive integers;
  DB constraints enforce bounds and uniqueness per program.
  """
  def changeset(schema \\ %__MODULE__{}, attrs) do
    schema
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:min_enrollment, greater_than_or_equal_to: 1)
    |> validate_number(:max_enrollment, greater_than_or_equal_to: 1)
    |> validate_min_not_exceeds_max()
    |> unique_constraint(:program_id)
    |> check_constraint(:min_enrollment, name: :min_enrollment_positive)
    |> check_constraint(:max_enrollment, name: :max_enrollment_positive)
    |> check_constraint(:min_enrollment, name: :min_not_exceeds_max)
  end

  defp validate_min_not_exceeds_max(changeset) do
    min = get_field(changeset, :min_enrollment)
    max = get_field(changeset, :max_enrollment)

    if is_integer(min) and is_integer(max) and min > max do
      add_error(changeset, :min_enrollment, "must not exceed maximum enrollment")
    else
      changeset
    end
  end

  @doc """
  Returns true if the current enrollment count is below the maximum capacity.

  Always true when no `max_enrollment` is set (uncapped program).
  """
  @spec has_capacity?(t(), non_neg_integer()) :: boolean()
  def has_capacity?(%__MODULE__{max_enrollment: nil}, _count), do: true
  def has_capacity?(%__MODULE__{max_enrollment: max}, count), do: count < max

  @doc """
  Returns true if the current enrollment count meets the minimum threshold.

  Always true when no `min_enrollment` is set.
  """
  @spec meets_minimum?(t(), non_neg_integer()) :: boolean()
  def meets_minimum?(%__MODULE__{min_enrollment: nil}, _count), do: true
  def meets_minimum?(%__MODULE__{min_enrollment: min}, count), do: count >= min

  @doc """
  Returns the remaining enrollment capacity given the current active count.

  Returns `:unlimited` when no `max_enrollment` is set.
  Never returns a negative number — floors at 0.
  """
  @spec remaining_capacity(t(), non_neg_integer()) :: non_neg_integer() | :unlimited
  def remaining_capacity(%__MODULE__{max_enrollment: nil}, _count), do: :unlimited
  def remaining_capacity(%__MODULE__{max_enrollment: max}, count), do: max(max - count, 0)
end
