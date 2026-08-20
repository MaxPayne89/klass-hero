defmodule KlassHero.Enrollment.Domain.ReadModels.OutstandingInvite do
  @moduledoc """
  One participant invite a provider has sent that nobody has accepted yet,
  carrying the program it belongs to.

  Query-shaped struct over the write tables — no schema twin, no read table, no
  changeset. Built by `Enrollment.list_outstanding_invites_for_provider/1`, which
  narrows a `BulkEnrollmentInvite` and attaches the program title the invite row
  itself does not carry.

  Field names deliberately mirror `BulkEnrollmentInvite`'s, so one invite-table
  component renders both this struct and the raw schema without a mapper between
  them (`#1073`). `program_title` is the only field the schema has no answer for.
  """

  alias KlassHero.Enrollment.BulkEnrollmentInvite

  @typedoc "A provider-wide outstanding invite row for the Overview card."
  @type t :: %__MODULE__{
          id: String.t(),
          program_id: String.t(),
          program_title: String.t() | nil,
          child_first_name: String.t(),
          child_last_name: String.t(),
          guardian_email: String.t(),
          status: :pending | :invite_sent | :failed,
          failure_code: atom() | nil,
          failure_context: map() | nil,
          error_details: String.t() | nil,
          inserted_at: DateTime.t()
        }

  @enforce_keys [
    :id,
    :program_id,
    :child_first_name,
    :child_last_name,
    :guardian_email,
    :status,
    :inserted_at
  ]

  defstruct [
    :id,
    :program_id,
    :program_title,
    :child_first_name,
    :child_last_name,
    :guardian_email,
    :status,
    :failure_code,
    :failure_context,
    :error_details,
    :inserted_at
  ]

  @doc """
  Builds a row from an invite and the title of the program it belongs to.

  `program_title` may be `nil` when the program row is gone; the caller renders a
  placeholder rather than dropping the invite, which would hide an invite the
  provider still needs to act on.
  """
  @spec from_invite(BulkEnrollmentInvite.t(), String.t() | nil) :: t()
  def from_invite(%BulkEnrollmentInvite{} = invite, program_title) do
    %__MODULE__{
      id: to_string(invite.id),
      program_id: to_string(invite.program_id),
      program_title: program_title,
      child_first_name: invite.child_first_name,
      child_last_name: invite.child_last_name,
      guardian_email: invite.guardian_email,
      status: invite.status,
      failure_code: invite.failure_code,
      failure_context: invite.failure_context,
      error_details: invite.error_details,
      inserted_at: invite.inserted_at
    }
  end
end
