defmodule KlassHero.Provider.ReadModels.ProgramStaffing do
  @moduledoc """
  Read-model of who currently staffs one program: the lead (if any) plus every
  active member.

  Powers the provider programs table (#1310). Before it, that table read the lead
  alone, so a staffed-but-leaderless program was indistinguishable from an empty
  one — and, worse, the staff *filter* matched on the rendered lead, which made
  "who is shown" define "who is findable". This struct is the single answer to
  both questions: `Presenters.ProgramPresenter` formats it, the LiveView filters
  through `staffed_by?/2`, and neither re-derives the other's semantics.

  `member_ids` carries **everyone active on the program, the lead included**, so
  `member_count == length(member_ids)` holds unconditionally and no caller needs
  a "lead or member?" branch. `lead.id` is therefore always a member of
  `member_ids` when `lead` is non-nil.

  "Active" means what the assignment reads already mean: the assignment has no
  `unassigned_at`, and the staff member's `active` flag is set. Display-optimized;
  the only logic here is the membership predicate.
  """

  @typedoc "The lead instructor shaped for display, or nil when the program has none."
  @type lead :: %{id: String.t(), name: String.t(), headshot_url: String.t() | nil} | nil

  @typedoc "Active staffing of one program."
  @type t :: %__MODULE__{
          program_id: String.t(),
          lead: lead(),
          member_ids: [String.t()],
          member_count: non_neg_integer()
        }

  @enforce_keys [:program_id, :member_ids, :member_count]

  defstruct [
    :program_id,
    :lead,
    member_ids: [],
    member_count: 0
  ]

  @doc """
  The zero-staff value. Batch reads omit programs nobody is on, so callers
  default to this rather than carrying a `nil` through the presenter.
  """
  @spec empty(String.t()) :: t()
  def empty(program_id) when is_binary(program_id) do
    %__MODULE__{program_id: program_id, lead: nil, member_ids: [], member_count: 0}
  end

  @doc """
  Whether `staff_member_id` is currently on this program, leading it or not.

  Accepts `nil` so a caller can pass a batch-read lookup straight through
  without first defaulting an absent program.
  """
  @spec staffed_by?(t() | nil, String.t()) :: boolean()
  def staffed_by?(nil, _staff_member_id), do: false

  def staffed_by?(%__MODULE__{member_ids: member_ids}, staff_member_id) do
    staff_member_id in member_ids
  end
end
