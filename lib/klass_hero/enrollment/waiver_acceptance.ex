defmodule KlassHero.Enrollment.WaiverAcceptance do
  @moduledoc """
  A parent's signature on one waiver version, bound to one enrollment
  (`waiver_acceptances` table).

  This module is both the Ecto schema and the struct consumers pattern-match. The changeset
  is the validation gatekeeper; `accept/3` is the functional core that builds the record
  from the version being signed.

  ## What makes this evidence

  The row references the exact `WaiverVersion` signed, and separately copies that version's
  text into `body_snapshot`. The version row is the source of truth; the snapshot is
  deliberate redundancy that survives even a catastrophic loss of the versions table. Both
  are required — an acceptance that cannot produce the text agreed to proves nothing.

  Append-only. A later version of the same waiver produces no change here: what was signed
  stays signed, at the version it was signed against.

  `ip_address` is nullable on purpose. When no trustworthy client IP is available the field
  stays `nil` rather than recording the proxy's address, which would look like evidence
  without being any.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.Enrollment.WaiverVersion

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "waiver_acceptances" do
    field :waiver_version_id, :binary_id
    field :waiver_id, :binary_id
    field :enrollment_id, :binary_id
    field :parent_id, :binary_id
    field :accepted_at, :utc_datetime_usec
    field :ip_address, :string
    field :user_agent, :string
    field :body_snapshot, :string

    timestamps()
  end

  @type t :: %__MODULE__{}

  @required ~w(waiver_version_id waiver_id enrollment_id parent_id accepted_at body_snapshot)a
  @optional ~w(ip_address user_agent)a

  @doc "Insert changeset. There is no update counterpart — a signature is never edited."
  def changeset(%__MODULE__{} = acceptance, attrs) do
    acceptance
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> unique_constraint([:enrollment_id, :waiver_id],
      name: :waiver_acceptances_enrollment_id_waiver_id_index,
      message: "already signed for this enrollment"
    )
    |> foreign_key_constraint(:waiver_version_id)
    |> foreign_key_constraint(:waiver_id)
    |> foreign_key_constraint(:enrollment_id)
  end

  @doc """
  Builds the attributes for a signature on `version`.

  `signer` carries `:enrollment_id` and `:parent_id`; `audit` optionally carries
  `:ip_address` and `:user_agent`. Missing audit keys stay `nil` — see the moduledoc.
  """
  @spec accept(WaiverVersion.t(), map(), map()) :: map()
  def accept(%WaiverVersion{} = version, signer, audit) do
    %{
      waiver_version_id: version.id,
      waiver_id: version.waiver_id,
      enrollment_id: signer.enrollment_id,
      parent_id: signer.parent_id,
      accepted_at: DateTime.utc_now(),
      ip_address: Map.get(audit, :ip_address),
      user_agent: Map.get(audit, :user_agent),
      body_snapshot: version.body
    }
  end
end
