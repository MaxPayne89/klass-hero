defmodule KlassHero.Enrollment.Domain.Models.EnrollmentPolicy do
  @moduledoc """
  Domain model representing enrollment capacity constraints for a program.

  Owned by the Enrollment context. Providers configure min/max enrollment
  when creating programs; the enrollment context enforces these limits.

  ## Capacity Rules

  - `min_enrollment` — minimum headcount needed for a program to run
  - `max_enrollment` — hard cap; no further enrollments once reached
  - At least one of min or max must be set

  Both limits are optional individually, but the policy must carry at
  least one constraint to be meaningful.
  """

  @enforce_keys [:program_id]

  defstruct [
    :id,
    :program_id,
    :min_enrollment,
    :max_enrollment,
    :inserted_at,
    :updated_at
  ]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          program_id: String.t(),
          min_enrollment: pos_integer() | nil,
          max_enrollment: pos_integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc """
  Creates a new EnrollmentPolicy from the given attributes.

  Returns `{:ok, policy}` on success or `{:error, errors}` with a list
  of human-readable validation messages.
  """
  @spec new(map()) :: {:ok, t()} | {:error, [String.t()]}
  def new(attrs) when is_map(attrs) do
    errors =
      []
      |> validate_program_id(attrs[:program_id])
      |> validate_min(attrs[:min_enrollment])
      |> validate_max(attrs[:max_enrollment])
      |> validate_min_max_relationship(attrs[:min_enrollment], attrs[:max_enrollment])
      |> validate_at_least_one(attrs[:min_enrollment], attrs[:max_enrollment])

    if errors == [] do
      {:ok,
       %__MODULE__{
         id: attrs[:id],
         program_id: attrs[:program_id],
         min_enrollment: attrs[:min_enrollment],
         max_enrollment: attrs[:max_enrollment],
         inserted_at: attrs[:inserted_at],
         updated_at: attrs[:updated_at]
       }}
    else
      {:error, errors}
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

  defp validate_program_id(errors, id) when is_binary(id) and byte_size(id) > 0, do: errors
  defp validate_program_id(errors, _), do: ["program ID is required" | errors]

  defp validate_min(errors, nil), do: errors
  defp validate_min(errors, min) when is_integer(min) and min >= 1, do: errors
  defp validate_min(errors, _), do: ["minimum enrollment must be at least 1" | errors]

  defp validate_max(errors, nil), do: errors
  defp validate_max(errors, max) when is_integer(max) and max >= 1, do: errors
  defp validate_max(errors, _), do: ["maximum enrollment must be at least 1" | errors]

  defp validate_min_max_relationship(errors, min, max) when is_integer(min) and is_integer(max) and min > max do
    ["minimum enrollment must not exceed maximum enrollment" | errors]
  end

  defp validate_min_max_relationship(errors, _min, _max), do: errors

  defp validate_at_least_one(errors, nil, nil) do
    ["at least one of minimum or maximum enrollment is required" | errors]
  end

  defp validate_at_least_one(errors, _min, _max), do: errors
end
