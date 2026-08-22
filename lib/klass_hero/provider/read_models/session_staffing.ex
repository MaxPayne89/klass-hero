defmodule KlassHero.Provider.ReadModels.SessionStaffing do
  @moduledoc """
  Read-model of who is on one session: the lead (if any), every active member, and
  **where the answer came from**.

  The session-grain counterpart of
  `KlassHero.Provider.ReadModels.ProgramStaffing`. Staffing has two grains —
  a program's default roster and a per-session override — and this struct is the
  single answer to "who is actually working this session".

  `source` is the fact that makes the two grains legible:

  * `:program` — the session carries no overrides and inherits the program roster.
  * `:override` — a provider deliberately staffed this session, and these rows
    *replace* the program roster rather than adding to it. That is what makes
    "two staff splitting a weekly schedule" expressible: each session names
    exactly who works it.

  `member_ids` carries **everyone active on the session, the lead included**, so
  `member_count == length(member_ids)` holds unconditionally and no caller needs a
  "lead or member?" branch — the same guarantee `ProgramStaffing` gives.

  Built only by `KlassHero.Provider.Assignments.get_session_staffing/1` and its
  batch sibling. Nothing else re-derives the override-vs-program rule; that
  duplication is what made the program-grain reads drift in #1310.
  """

  @typedoc "The lead instructor shaped for display, or nil when the session has none."
  @type lead :: %{id: String.t(), name: String.t(), headshot_url: String.t() | nil} | nil

  @typedoc "Whether this roster is the program's default or an override for this session."
  @type source :: :program | :override

  @typedoc "Active staffing of one session."
  @type t :: %__MODULE__{
          session_id: String.t(),
          program_id: String.t(),
          lead: lead(),
          member_ids: [String.t()],
          member_count: non_neg_integer(),
          source: source(),
          program_closed?: boolean()
        }

  @enforce_keys [:session_id, :program_id, :member_ids, :member_count, :source, :program_closed?]

  defstruct [
    :session_id,
    :program_id,
    :lead,
    member_ids: [],
    member_count: 0,
    source: :program,
    program_closed?: false
  ]

  @doc """
  The zero-staff value.

  `source` is `:program`, not `:override`: a session nobody staffs is inheriting an
  empty program roster. An override is a row a provider deliberately created, so
  "no rows anywhere" can never be one.

  `program_closed?` still has to be carried: having no staff and belonging to a
  closed program are independent facts, and the caller knows the second one.
  """
  @spec empty(String.t(), String.t(), boolean()) :: t()
  def empty(session_id, program_id, program_closed? \\ false)
      when is_binary(session_id) and is_binary(program_id) and is_boolean(program_closed?) do
    %__MODULE__{
      session_id: session_id,
      program_id: program_id,
      lead: nil,
      member_ids: [],
      member_count: 0,
      source: :program,
      program_closed?: program_closed?
    }
  end

  @doc """
  Whether `staff_member_id` may act on this session: on it, and its program still
  open.

  Accepts `nil` so a caller can pass a batch-read lookup straight through without
  first defaulting an absent session.

  A **Closed Program** refuses everyone, member and lead alike (#1082). The check
  lives here rather than at the five call sites because every one of them is an
  authorization decision, and a rule they each have to remember is a rule one of
  them eventually forgets — which is what #1323 was.
  """
  @spec staffed_by?(t() | nil, String.t()) :: boolean()
  def staffed_by?(nil, _staff_member_id), do: false
  def staffed_by?(%__MODULE__{program_closed?: true}, _staff_member_id), do: false

  def staffed_by?(%__MODULE__{member_ids: member_ids}, staff_member_id) do
    staff_member_id in member_ids
  end

  @doc "Whether `staff_member_id` leads this session. Closed programs have no lead to act."
  @spec led_by?(t() | nil, String.t()) :: boolean()
  def led_by?(nil, _staff_member_id), do: false
  def led_by?(%__MODULE__{program_closed?: true}, _staff_member_id), do: false
  def led_by?(%__MODULE__{lead: nil}, _staff_member_id), do: false
  def led_by?(%__MODULE__{lead: %{id: lead_id}}, staff_member_id), do: lead_id == staff_member_id

  @doc """
  Whether this roster was deliberately overridden for the session.

  The UI needs the distinction to say so, and to decide whether "revert to the
  program roster" is a meaningful action.
  """
  @spec overridden?(t()) :: boolean()
  def overridden?(%__MODULE__{source: :override}), do: true
  def overridden?(%__MODULE__{}), do: false
end
