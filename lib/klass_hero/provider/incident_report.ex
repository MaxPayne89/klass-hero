defmodule KlassHero.Provider.IncidentReport do
  @moduledoc """
  Provider incident report (`incident_reports` table).

  Owned by the Provider context. Polymorphic by scope: a report is tied to
  exactly one of `program_id` or `session_id`, never both — enforced in the
  changeset and backed by a DB CHECK constraint.

  This module is both the Ecto schema and the struct consumers pattern-match.
  `create_changeset/1` is the single validation gatekeeper; the label helpers
  and `valid_*` lists are the functional core.

  ## Field naming

  The struct field is `provider_profile_id` (semantic clarity) but the DB column
  is `provider_id`, which references the `providers` table. The `source:` option
  carries the mapping so consumers keep reading `report.provider_profile_id`.

  ## Admin affordances

  `provider_name` and `program_title` are **virtual** — nothing in the write path
  populates them. They exist for `KlassHeroWeb.Admin.IncidentLive`, whose
  `item_query/3` joins the owning provider and program and merges the names in.
  Virtual fields rather than `belongs_to` associations deliberately: an
  association added for a Backpex field becomes an invisible consumer, so a later
  removal breaks the admin view silently.

  `admin_changeset/3` is inert config, not a second validation path —
  `create_changeset/1` remains the only gatekeeper.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  @categories [
    :safety_concern,
    :behavioral_issue,
    :injury,
    :property_damage,
    :policy_violation,
    :other
  ]

  @severities [:low, :medium, :high, :critical]

  @min_description_length 10

  schema "incident_reports" do
    field :provider_profile_id, :binary_id, source: :provider_id
    field :reporter_user_id, :binary_id
    field :reporter_display_name, :string
    field :program_id, :binary_id
    field :session_id, :binary_id
    field :category, Ecto.Enum, values: @categories
    field :severity, Ecto.Enum, values: @severities
    field :description, :string
    field :occurred_at, :utc_datetime
    field :photo_url, :string
    field :original_filename, :string

    # Populated only by KlassHeroWeb.Admin.IncidentLive's item_query/3 join.
    field :provider_name, :string, virtual: true
    field :program_title, :string, virtual: true

    timestamps()
  end

  @type t :: %__MODULE__{}

  @type category ::
          :safety_concern
          | :behavioral_issue
          | :injury
          | :property_damage
          | :policy_violation
          | :other

  @type severity :: :low | :medium | :high | :critical

  @required_fields ~w(id provider_profile_id reporter_user_id reporter_display_name category severity description occurred_at)a
  @optional_fields ~w(program_id session_id photo_url original_filename)a

  @doc "Returns the list of valid incident categories."
  @spec valid_categories() :: [category()]
  def valid_categories, do: @categories

  @doc "Returns the list of valid incident severities."
  @spec valid_severities() :: [severity()]
  def valid_severities, do: @severities

  @doc "Plain English label for a category atom."
  @spec category_label(category()) :: String.t()
  def category_label(:safety_concern), do: "Safety concern"
  def category_label(:behavioral_issue), do: "Behavioral issue"
  def category_label(:injury), do: "Injury"
  def category_label(:property_damage), do: "Property damage"
  def category_label(:policy_violation), do: "Policy violation"
  def category_label(:other), do: "Other"

  @doc "Plain English label for a severity atom."
  @spec severity_label(severity()) :: String.t()
  def severity_label(:low), do: "Low"
  def severity_label(:medium), do: "Medium"
  def severity_label(:high), do: "High"
  def severity_label(:critical), do: "Critical"

  @doc """
  Changeset for inserting an incident report — the single validation gatekeeper.

  Folds the former domain `new/1` invariants (exactly-one-target, non-future
  `occurred_at`, min description length, photo pairing, present reporter name)
  and the schema-level FK/CHECK constraints into one place. `Ecto.Enum` rejects
  invalid `category`/`severity` on cast, so no manual inclusion check is needed.
  """
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:description, min: @min_description_length)
    |> validate_occurred_at_not_future()
    |> validate_exactly_one_target()
    |> validate_photo_pair()
    |> check_constraint(:target,
      name: :one_of_program_or_session,
      message: "exactly one of program_id or session_id must be set"
    )
    |> check_constraint(:category, name: :category_check, message: "is invalid")
    |> check_constraint(:severity, name: :severity_check, message: "is invalid")
    |> foreign_key_constraint(:provider_profile_id, name: :incident_reports_provider_id_fkey)
    |> foreign_key_constraint(:reporter_user_id)
    |> foreign_key_constraint(:program_id)
    |> foreign_key_constraint(:session_id)
  end

  @doc "No-op changeset required by Backpex even when edit is disabled via `can?/3`."
  def admin_changeset(schema, _attrs, _metadata), do: change(schema)

  defp validate_occurred_at_not_future(changeset) do
    validate_change(changeset, :occurred_at, fn :occurred_at, occurred_at ->
      case DateTime.compare(occurred_at, DateTime.utc_now()) do
        :gt -> [occurred_at: "cannot be in the future"]
        _ -> []
      end
    end)
  end

  defp validate_exactly_one_target(changeset) do
    program_id = get_field(changeset, :program_id)
    session_id = get_field(changeset, :session_id)

    case {program_id, session_id} do
      {pid, nil} when is_binary(pid) -> changeset
      {nil, sid} when is_binary(sid) -> changeset
      _ -> add_error(changeset, :target, "exactly one of program_id or session_id must be set")
    end
  end

  defp validate_photo_pair(changeset) do
    url = get_field(changeset, :photo_url)
    name = get_field(changeset, :original_filename)

    if is_binary(url) and not (is_binary(name) and name != "") do
      add_error(changeset, :original_filename, "is required when photo_url is set")
    else
      changeset
    end
  end
end
