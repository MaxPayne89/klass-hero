defmodule KlassHero.Enrollment.WaiverVersion do
  @moduledoc """
  One published wording of a `Waiver` (`waiver_versions` table).

  This module is both the Ecto schema and the struct consumers pattern-match. The changeset
  is the validation gatekeeper; `publish/3` is the functional core that allocates the next
  version number.

  ## Append-only, and why it has to be

  A row here is never updated. Editing a waiver's wording publishes a *new* version; the old
  row stays exactly as signed. That is the whole point: a recorded version number is
  worthless as evidence unless its text is reproducible verbatim, the same rule
  `Provider.CommunityGuidelines` states for the platform's own agreements. Storing the body
  on the waiver and bumping a counter would lose the wording of any version nobody happened
  to sign — leaving audit holes precisely where a provider revised a form before anyone
  signed it.

  There is deliberately no `update_changeset/2`. Do not add one.

  A version already signed also cannot be deleted: `waiver_acceptances` references it with
  `on_delete: :restrict`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  # Long-form legal text; generous, but bounded so a runaway paste cannot fill the column.
  @body_max 50_000

  schema "waiver_versions" do
    field :waiver_id, :binary_id
    field :body, :string
    field :version, :integer
    field :published_at, :utc_datetime_usec

    timestamps()
  end

  @type t :: %__MODULE__{}

  @doc "Maximum body length, enforced in the changeset rather than as a column cap."
  def body_max_length, do: @body_max

  @doc """
  Insert changeset. There is no update counterpart — see the moduledoc.
  """
  def changeset(%__MODULE__{} = version, attrs) do
    version
    |> cast(attrs, [:waiver_id, :body, :version, :published_at])
    |> validate_required([:waiver_id, :body, :version, :published_at])
    |> validate_length(:body, max: @body_max)
    |> validate_number(:version, greater_than_or_equal_to: 1)
    |> validate_body_present()
    |> unique_constraint([:waiver_id, :version],
      name: :waiver_versions_waiver_id_version_index,
      message: "already published"
    )
    |> foreign_key_constraint(:waiver_id)
    |> check_constraint(:version, name: :waiver_version_positive)
  end

  @doc """
  Builds the attributes for the next version of a waiver.

  `previous` is the waiver's current latest version, or `nil` when nothing has been
  published yet. Returns `{:ok, attrs}` or `{:error, [{field, message}]}`.

  The body is trimmed, because trailing whitespace differences would otherwise produce a new
  legal version that reads identically to the last one.
  """
  @spec publish(binary(), String.t() | nil, t() | nil) :: {:ok, map()} | {:error, keyword()}
  def publish(waiver_id, body, previous) do
    trimmed = body |> to_string() |> String.trim()

    cond do
      trimmed == "" ->
        {:error, [body: "is required"]}

      String.length(trimmed) > @body_max ->
        {:error, [body: "is too long"]}

      true ->
        {:ok,
         %{
           waiver_id: waiver_id,
           body: trimmed,
           version: next_version(previous),
           published_at: DateTime.utc_now()
         }}
    end
  end

  defp next_version(nil), do: 1
  defp next_version(%__MODULE__{version: version}), do: version + 1

  defp validate_body_present(changeset) do
    case get_field(changeset, :body) do
      nil -> changeset
      body -> if String.trim(body) == "", do: add_error(changeset, :body, "is required"), else: changeset
    end
  end
end
