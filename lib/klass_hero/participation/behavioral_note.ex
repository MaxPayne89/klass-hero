defmodule KlassHero.Participation.BehavioralNote do
  @moduledoc """
  A behavioral note about a child's participation: the Ecto schema and the
  struct other code pattern-matches on, plus the approval state machine.

  ## Status Lifecycle

  ```
  :pending_approval → :approved (final)
  :pending_approval → :rejected → (revise) → :pending_approval
  ```

  Providers submit notes on checked-in/checked-out records. Parents approve or
  reject. Rejected notes can be revised and resubmitted.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KlassHero.Participation.ParticipationRecord

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "behavioral_notes" do
    field :child_id, :binary_id
    field :parent_id, :binary_id
    field :provider_id, :binary_id
    field :content, :string
    field :status, Ecto.Enum, values: [:pending_approval, :approved, :rejected]
    field :rejection_reason, :string
    field :submitted_at, :utc_datetime
    field :reviewed_at, :utc_datetime

    belongs_to :participation_record, ParticipationRecord

    timestamps(type: :utc_datetime)
  end

  @type status :: :pending_approval | :approved | :rejected
  @type t :: %__MODULE__{}

  @valid_statuses [:pending_approval, :approved, :rejected]
  @max_content_length 1000

  @required_fields [:participation_record_id, :child_id, :provider_id, :content, :status, :submitted_at]
  @optional_fields [:parent_id, :rejection_reason, :reviewed_at]

  @doc "Creates a changeset for inserting a new behavioral note."
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_length(:content, max: @max_content_length)
    |> unique_constraint([:participation_record_id, :provider_id],
      name: :behavioral_notes_participation_record_id_provider_id_index,
      message: "note already exists for this provider and record"
    )
    |> foreign_key_constraint(:participation_record_id)
    |> foreign_key_constraint(:child_id)
  end

  @doc "Creates a changeset for updating an existing behavioral note."
  def update_changeset(note, attrs) do
    note
    |> cast(attrs, [:content, :status, :rejection_reason, :submitted_at, :reviewed_at])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_length(:content, max: @max_content_length)
  end

  @doc "Builds a pending-approval note. Content must be non-blank and at most #{@max_content_length} chars."
  @spec new(map()) ::
          {:ok, t()} | {:error, :missing_required_fields | :blank_content | :content_too_long}
  def new(attrs) when is_map(attrs) do
    with {:ok, id} <- Map.fetch(attrs, :id),
         {:ok, participation_record_id} <- Map.fetch(attrs, :participation_record_id),
         {:ok, child_id} <- Map.fetch(attrs, :child_id),
         {:ok, provider_id} <- Map.fetch(attrs, :provider_id),
         {:ok, content} <- Map.fetch(attrs, :content),
         :ok <- validate_content(content) do
      {:ok,
       %__MODULE__{
         id: id,
         participation_record_id: participation_record_id,
         child_id: child_id,
         parent_id: Map.get(attrs, :parent_id),
         provider_id: provider_id,
         content: String.trim(content),
         status: :pending_approval,
         submitted_at: DateTime.utc_now()
       }}
    else
      :error -> {:error, :missing_required_fields}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Approves a pending note. Errors unless `:pending_approval`."
  @spec approve(t()) :: {:ok, t()} | {:error, :invalid_status_transition}
  def approve(%__MODULE__{status: :pending_approval} = note) do
    {:ok, %{note | status: :approved, reviewed_at: DateTime.utc_now()}}
  end

  def approve(%__MODULE__{}), do: {:error, :invalid_status_transition}

  @doc "Rejects a pending note with an optional reason. Errors unless `:pending_approval`."
  @spec reject(t(), String.t() | nil) :: {:ok, t()} | {:error, :invalid_status_transition}
  def reject(note, reason \\ nil)

  def reject(%__MODULE__{status: :pending_approval} = note, reason) do
    {:ok, %{note | status: :rejected, rejection_reason: reason, reviewed_at: DateTime.utc_now()}}
  end

  def reject(%__MODULE__{}, _reason), do: {:error, :invalid_status_transition}

  @doc """
  Revises a rejected note with new content, resubmitting for approval. Errors
  unless `:rejected`. Clears rejection_reason and resets submitted_at.
  """
  @spec revise(t(), String.t()) ::
          {:ok, t()} | {:error, :invalid_status_transition | :blank_content | :content_too_long}
  def revise(%__MODULE__{status: :rejected} = note, new_content) when is_binary(new_content) do
    with :ok <- validate_content(new_content) do
      {:ok,
       %{
         note
         | content: String.trim(new_content),
           status: :pending_approval,
           rejection_reason: nil,
           submitted_at: DateTime.utc_now(),
           reviewed_at: nil
       }}
    end
  end

  def revise(%__MODULE__{}, _content), do: {:error, :invalid_status_transition}

  @doc "Returns true if the note is pending approval."
  @spec pending?(t()) :: boolean()
  def pending?(%__MODULE__{status: :pending_approval}), do: true
  def pending?(%__MODULE__{}), do: false

  @doc "Returns true if the note is approved."
  @spec approved?(t()) :: boolean()
  def approved?(%__MODULE__{status: :approved}), do: true
  def approved?(%__MODULE__{}), do: false

  @doc "Returns true if the note is rejected."
  @spec rejected?(t()) :: boolean()
  def rejected?(%__MODULE__{status: :rejected}), do: true
  def rejected?(%__MODULE__{}), do: false

  @doc "Returns anonymized attribute values for GDPR account deletion."
  def anonymized_attrs do
    %{
      content: "[Removed - account deleted]",
      rejection_reason: nil,
      status: :rejected
    }
  end

  defp validate_content(content) when is_binary(content) do
    trimmed = String.trim(content)

    cond do
      trimmed == "" -> {:error, :blank_content}
      String.length(trimmed) > @max_content_length -> {:error, :content_too_long}
      true -> :ok
    end
  end

  defp validate_content(_), do: {:error, :blank_content}
end
