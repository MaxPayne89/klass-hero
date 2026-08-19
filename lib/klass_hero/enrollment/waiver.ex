defmodule KlassHero.Enrollment.Waiver do
  @moduledoc """
  A provider-authored legal waiver attached to a program (`waivers` table).

  Owned by the Enrollment context, beside `ParticipantPolicy` and `EnrollmentPolicy`:
  providers configure it, and the context enforces it during enrollment. A `required`
  waiver blocks self-serve enrollment until it is signed.

  This module is both the Ecto schema and the struct consumers pattern-match. The changeset
  is the validation gatekeeper; `active?/1` and `archived?/1` are the functional core.

  ## Identity, not text

  A waiver row carries no body. The text lives in `WaiverVersion` rows, appended one per
  edit, so a signature can be bound to the exact wording it was given. Editing a waiver's
  wording therefore never touches this table.

  ## Retirement is archival, never deletion

  `archived_at` retires a waiver from future enrollments while leaving every signature under
  it intact and its text reproducible. Hard-deleting the row would destroy the referent of a
  legal record, which is the one outcome this feature exists to prevent — the DB refuses it
  too (`:restrict` on the acceptance FKs). `archived_at` is not castable: it moves only
  through `archive_changeset/2`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @title_max 200

  schema "waivers" do
    field :program_id, :binary_id
    field :title, :string
    field :required, :boolean, default: true
    field :archived_at, :utc_datetime_usec

    timestamps()
  end

  @type t :: %__MODULE__{}

  @doc "Maximum title length, enforced here rather than as a column cap."
  def title_max_length, do: @title_max

  @doc """
  Changeset for creating or renaming a waiver.

  `archived_at` is deliberately absent from the cast list — see the moduledoc.
  """
  def changeset(%__MODULE__{} = waiver, attrs) do
    waiver
    |> cast(attrs, [:program_id, :title, :required])
    |> validate_required([:program_id, :title])
    |> validate_length(:title, max: @title_max)
  end

  @doc "Changeset that retires a waiver by stamping `archived_at`."
  def archive_changeset(%__MODULE__{} = waiver, %DateTime{} = archived_at) do
    change(waiver, %{archived_at: archived_at})
  end

  @doc "Whether the waiver still applies to new enrollments."
  @spec active?(t()) :: boolean()
  def active?(%__MODULE__{archived_at: nil}), do: true
  def active?(%__MODULE__{}), do: false

  @doc "Whether the waiver has been retired."
  @spec archived?(t()) :: boolean()
  def archived?(%__MODULE__{archived_at: nil}), do: false
  def archived?(%__MODULE__{}), do: true
end
